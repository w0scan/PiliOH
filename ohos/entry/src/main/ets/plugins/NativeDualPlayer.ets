import media from '@ohos.multimedia.media';
import avSession from '@ohos.multimedia.avsession';
import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager';
import wantAgent from '@ohos.app.ability.wantAgent';
import fileIo from '@ohos.file.fs';
import type common from '@ohos.app.ability.common';
import http from '@ohos.net.http';
import image from '@ohos.multimedia.image';
import {
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodCall,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import type { BusinessError } from '@ohos.base';
import { NativePlayerViewFactory, NativePlayerView } from './NativePlayerView';
import PiPManager from './PiPManager';

const TAG = 'NativeDualPlayer';

// Sync master: which track is the timing reference the other seeks to.
const MASTER_AUDIO = 0; // follower=video seeks to audio (default; audio-master)
const MASTER_VIDEO = 1; // follower=audio seeks to video

const DRIFT_SEEK_COOLDOWN_MS = 1000;

interface OpenedFile {
  fd: number;
}

interface PendingInit {
  videoUrl: string;
  audioUrl: string | null;
}

/** Source/lifecycle for the native dual AVPlayer (video + audio). */
export const VIEW_TYPE = 'piliplus/native_player_view';

/**
 * Native HarmonyOS dual-AVPlayer for Bilibili DASH (separate audio + video).
 * The VIDEO player is the muted main clock, rendering into a real XComponent
 * SURFACE provided by a PlatformView (NativePlayerView); the AUDIO player
 * outputs sound. Rendering into an XComponent surface (not a Flutter texture)
 * avoids the EGL/OH_NativeImage conflict that produced a black frame.
 *
 * Surface arrives asynchronously from the XComponent's onLoad, and setSource
 * arrives from Dart; whichever is last triggers startup (pendingInit gate),
 * matching the reference app's tryStartNative.
 */
export default class NativeDualPlayer implements FlutterPlugin {
  private channel: MethodChannel | null = null;

  // UIAbilityContext for background task / AVSession, set by EntryAbility.
  static abilityContext: common.UIAbilityContext | null = null;

  private videoPlayer: media.AVPlayer | null = null;
  private audioPlayer: media.AVPlayer | null = null;

  // Surface id from the XComponent (PlatformView). Empty until onLoad fires.
  private surfaceId: string = '';
  private pendingInit: PendingInit | null = null;

  private syncMaster: number = MASTER_AUDIO;
  private syncThresholdMs: number = 2000;
  private startMs: number = 0;
  private startSeekDone: boolean = true;
  private speed: number = 1.0;
  // Last speed actually pushed to the AVPlayers; -1 = never applied.
  // Lets applySpeed() push 1.0 to restore from long-press 2x while still
  // skipping redundant re-applies of an unchanged speed.
  private appliedSpeed: number = -1;
  private headers: Record<string, string> = {};

  private wantPlay: boolean = false;
  private videoReady: boolean = false;
  private audioReady: boolean = false;
  private lastDriftSeekTs: number = 0;

  // Monotonic id bumped on every setSource/release. Async teardown+setup
  // continuations capture it and bail if a newer op has superseded them, so a
  // stale video's events/setup can't touch the current players.
  private genId: number = 0;
  // Serializes teardown/setup so a previous video's players are fully released
  // (audio stopped, fds closed) before the next video's players are created —
  // otherwise a not-yet-released audio track keeps playing and a stale
  // timeUpdate drives correctDrift to seek the new video's track (stutter).
  private pending: Promise<void> = Promise.resolve();

  private openedFds: OpenedFile[] = [];

  // Video dimensions (updated on prepared), sent to Dart for aspect ratio.
  private videoWidth: number = 0;
  private videoHeight: number = 0;

  // Background playback: AVSession + long-running task keep the app alive
  // when the user switches away with "continue playing in background" on.
  private avSession: avSession.AVSession | null = null;
  private bgTaskRunning: boolean = false;

  // Media metadata for the AVSession notification.
  private mediaTitle: string = '';
  private mediaArtist: string = '';
  private mediaCoverUri: string = '';
  private mediaDurationMs: number = 0;
  private mediaIsLive: boolean = false;
  private mediaCoverPixelMap: image.PixelMap | null = null;

  getUniqueClassName(): string {
    return 'NativeDualPlayer';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(
      binding.getBinaryMessenger(),
      'piliplus/native_player',
    );
    this.channel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        this.handle(call, result);
      },
    });
    const reg = binding.getPlatformViewRegistry();
    const factory = new NativePlayerViewFactory(this);
    reg?.registerViewFactory(VIEW_TYPE, factory);
    // Register with PiPManager so PiP can switch the AVPlayer surface.
    PiPManager.getInstance().registerNativePlayer(this);
    Log.i(TAG, 'attached');
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    PiPManager.getInstance().unregisterNativePlayer();
    this.stopBackgroundPlayback();
    this.releaseAll();
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  // ----- surface lifecycle (from NativePlayerView / XComponent) -----

  onViewSurfaceReady(surfaceId: string): void {
    this.surfaceId = surfaceId;
    Log.i(TAG, 'onViewSurfaceReady: surfaceId=' + surfaceId + ', videoPlayer=' + (this.videoPlayer !== null) + ', pendingInit=' + (this.pendingInit !== null));
    // If already playing (e.g. fullscreen rebuild recreated the XComponent),
    // just rebind the new surface to the live video player.
    if (this.videoPlayer !== null && this.pendingInit === null) {
      try {
        this.videoPlayer.surfaceId = surfaceId;
        // Re-apply video scale type after surface rebinding to prevent
        // video stretching when the XComponent is recreated (e.g. fullscreen).
        try {
          this.videoPlayer.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_FIT;
        } catch (e) {
          Log.e(TAG, 're-apply videoScaleType failed: ' + JSON.stringify(e));
        }
        Log.i(TAG, 'onViewSurfaceReady: rebound surface to existing player');
      } catch (e) {
        Log.e(TAG, 'rebind surface failed: ' + JSON.stringify(e));
      }
      return;
    }
    this.tryStart();
  }

  onViewSurfaceDestroyed(): void {
    this.surfaceId = '';
    Log.i(TAG, 'onViewSurfaceDestroyed');
  }

  // ----- PiP surface switching (called by PiPManager) -----

  // Switch the video AVPlayer's surface to the PiP window's XComponent surface.
  // Called when a PiP session starts and the PiP surface is ready.
  enterPip(pipSurfaceId: string): void {
    if (this.videoPlayer === null) {
      Log.e(TAG, 'enterPip: no video player');
      return;
    }
    try {
      this.videoPlayer.surfaceId = pipSurfaceId;
      // Re-apply video scale type after surface switch.
      this.videoPlayer.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_FIT;
      Log.i(TAG, 'enterPip: switched video surface to pip: ' + pipSurfaceId);
    } catch (e) {
      Log.e(TAG, 'enterPip failed: ' + JSON.stringify(e));
    }
  }

  // Switch the video AVPlayer's surface back to the main XComponent surface.
  // Called when a PiP session ends.
  exitPip(): void {
    if (this.videoPlayer === null) {
      Log.e(TAG, 'exitPip: no video player');
      return;
    }
    if (this.surfaceId.length === 0) {
      Log.e(TAG, 'exitPip: no main surface id');
      return;
    }
    try {
      this.videoPlayer.surfaceId = this.surfaceId;
      this.videoPlayer.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_FIT;
      Log.i(TAG, 'exitPip: switched video surface back to main: ' + this.surfaceId);
    } catch (e) {
      Log.e(TAG, 'exitPip failed: ' + JSON.stringify(e));
    }
  }

  // -------------------------------------------------------------------------
  // MethodChannel dispatch
  // -------------------------------------------------------------------------
  private handle(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'setSource':
        this.setSource(call, result);
        break;
      case 'play':
        this.wantPlay = true;
        if (this.videoReady && this.audioReady) {
          this.playInternal();
        }
        result.success(null);
        break;
      case 'pause':
        this.wantPlay = false;
        this.videoPlayer?.pause();
        this.audioPlayer?.pause();
        result.success(null);
        break;
      case 'seek':
        this.seekBoth(call.args as number);
        result.success(null);
        break;
      case 'setSpeed':
        this.speed = call.args as number;
        this.applySpeed();
        result.success(null);
        break;
      case 'setVolume': {
        const v = Math.max(0, Math.min(1, call.args as number));
        try {
          if (this.audioPlayer !== null) {
            this.audioPlayer.setVolume(v);
          } else {
            this.videoPlayer?.setVolume(v);
          }
        } catch (e) {
          Log.e(TAG, 'setVolume failed: ' + JSON.stringify(e));
        }
        result.success(null);
        break;
      }
      case 'setSyncMaster':
        this.syncMaster = call.args as number;
        result.success(null);
        break;
      case 'setSyncThreshold':
        this.syncThresholdMs = call.args as number;
        result.success(null);
        break;
      case 'release':
        this.releaseAll();
        result.success(null);
        break;
      case 'setMediaMetadata': {
        this.mediaTitle = (call.argument('title') as string) ?? '';
        this.mediaArtist = (call.argument('artist') as string) ?? '';
        this.mediaCoverUri = (call.argument('coverUri') as string) ?? '';
        this.mediaDurationMs = (call.argument('durationMs') as number) ?? 0;
        this.mediaIsLive = (call.argument('isLive') as boolean) ?? false;
        // Set metadata with URI first, then load PixelMap for the cover image.
        this.updateAVMetadata();
        this.loadCoverImage(this.mediaCoverUri);
        result.success(null);
        break;
      }
      case 'updatePlaybackState': {
        const stateStr = call.argument('state') as string;
        const posMs = (call.argument('positionMs') as number) ?? 0;
        const speed = (call.argument('speed') as number) ?? 1.0;
        const bufferedMs = (call.argument('bufferedMs') as number) ?? 0;
        this.updateAVPlaybackState(stateStr, posMs, speed, bufferedMs);
        result.success(null);
        break;
      }
      default:
        result.notImplemented();
    }
  }

  // -------------------------------------------------------------------------
  // Source
  // -------------------------------------------------------------------------
  private setSource(call: MethodCall, result: MethodResult): void {
    const videoUrl = call.argument('videoUrl') as string;
    const audioUrl = call.argument('audioUrl') as string | null;
    this.headers = NativeDualPlayer.toRecord(call.argument('headers'));
    this.startMs = (call.argument('startMs') as number) ?? 0;
    this.startSeekDone = this.startMs <= 0;
    this.syncMaster = (call.argument('syncMaster') as number) ?? MASTER_AUDIO;
    this.syncThresholdMs =
      (call.argument('syncThresholdMs') as number) ?? 2000;
    Log.i(TAG, 'setSource: video=' + videoUrl.substring(0, Math.min(videoUrl.length, 60)) + '..., audio=' + (audioUrl != null ? 'yes' : 'no') + ', startMs=' + this.startMs + ', surfaceId=' + this.surfaceId);
    this.pendingInit = { videoUrl, audioUrl };
    this.tryStart();
    result.success(null);
  }

  // Start the players once BOTH the source params and the XComponent surface
  // are ready; whichever arrives last calls this.
  private tryStart(): void {
    const init = this.pendingInit;
    if (init === null || this.surfaceId.length === 0) {
      Log.i(TAG, 'tryStart: pending=' + (init !== null) + ', surfaceId=' + this.surfaceId + ' (waiting)');
      return;
    }
    this.pendingInit = null;
    Log.i(TAG, 'tryStart: starting setupPlayers');
    const gen = ++this.genId;
    this.runExclusive((): Promise<void> => {
      if (gen !== this.genId) {
        return Promise.resolve();
      }
      return this.resetPlayers().then((): Promise<void> => {
        if (gen !== this.genId) {
          return Promise.resolve();
        }
        return this.setupPlayers(init.videoUrl, init.audioUrl);
      });
    }).catch((e: BusinessError): void => {
      Log.e(TAG, 'setup failed: ' + JSON.stringify(e));
      this.channel?.invokeMethod('onError', '原生播放器初始化失败: ' + e.message);
    });
  }

  // Chain async teardown/setup so they never interleave on the shared player
  // fields / fd list. Each op waits for the previous to settle.
  private runExclusive(op: () => Promise<void>): Promise<void> {
    const next = this.pending.then(
      (): Promise<void> => op(),
      (): Promise<void> => op(),
    );
    this.pending = next.catch((): void => {});
    return next;
  }

  private async setupPlayers(
    videoSrc: string,
    audioSrc: string | null,
  ): Promise<void> {
    Log.i(TAG, 'setupPlayers: start');
    this.videoPlayer = await media.createAVPlayer();
    this.bindVideoEvents(this.videoPlayer);
    Log.i(TAG, 'setupPlayers: video player created, applying source');
    await this.applySource(this.videoPlayer, videoSrc);

    if (audioSrc != null && audioSrc.length > 0) {
      this.audioPlayer = await media.createAVPlayer();
      this.bindAudioEvents(this.audioPlayer);
      Log.i(TAG, 'setupPlayers: audio player created, applying source');
      await this.applySource(this.audioPlayer, audioSrc);
    } else {
      this.audioReady = true;
      Log.i(TAG, 'setupPlayers: no audio track, audioReady=true');
    }
    Log.i(TAG, 'setupPlayers: done, videoReady=' + this.videoReady + ', audioReady=' + this.audioReady);
  }

  private async applySource(player: media.AVPlayer, src: string): Promise<void> {
    if (src.startsWith('http')) {
      const source: media.MediaSource = media.createMediaSourceWithUrl(
        src,
        this.headers,
      );
      await player.setMediaSource(source);
    } else {
      player.fdSrc = this.openFd(src);
    }
  }

  private openFd(path: string): media.AVFileDescriptor {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    const size = fileIo.statSync(path).size;
    this.openedFds.push({ fd: file.fd });
    return { fd: file.fd, offset: 0, length: size };
  }

  // -------------------------------------------------------------------------
  // Player wiring
  // -------------------------------------------------------------------------
  private bindVideoEvents(p: media.AVPlayer): void {
    p.on('stateChange', (state: string): void => {
      // Ignore events from a player that's no longer the current one (a stale
      // video being torn down must not flip ready flags or trigger maybeStart).
      if (p !== this.videoPlayer) {
        return;
      }
      Log.i(TAG, 'video stateChange: ' + state);
      if (state === 'initialized') {
        p.surfaceId = this.surfaceId;
        p.prepare();
      } else if (state === 'prepared') {
        // Preserve aspect ratio (letterbox) instead of stretching the video to
        // fill the XComponent — fixes portrait videos being stretched wide.
        try {
          p.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_FIT;
        } catch (e) {
          Log.e(TAG, 'setVideoScaleType failed: ' + JSON.stringify(e));
        }
        // Capture video dimensions and notify Dart side.
        try {
          this.videoWidth = p.width;
          this.videoHeight = p.height;
          Log.i(TAG, 'video prepared: size=' + this.videoWidth + 'x' + this.videoHeight);
          this.channel?.invokeMethod('onVideoSize', { w: this.videoWidth, h: this.videoHeight });
        } catch (e) {
          Log.e(TAG, 'get video size failed: ' + JSON.stringify(e));
        }
        p.setVolume(this.audioPlayer !== null ? 0 : 1);
        this.videoReady = true;
        Log.i(TAG, 'video prepared, videoReady=true, calling maybeStart');
        this.maybeStart();
      } else if (state === 'playing') {
        Log.i(TAG, 'video playing → onPlayingChanged(true)');
        this.channel?.invokeMethod('onPlayingChanged', true);
        this.startBackgroundPlayback();
      } else if (state === 'paused') {
        Log.i(TAG, 'video paused → onPlayingChanged(false)');
        this.channel?.invokeMethod('onPlayingChanged', false);
        this.stopBackgroundPlayback();
      } else if (state === 'completed') {
        Log.i(TAG, 'video completed → onCompleted');
        this.channel?.invokeMethod('onCompleted', null);
        this.stopBackgroundPlayback();
      } else if (state === 'stopped' || state === 'released' || state === 'idle') {
        Log.i(TAG, 'video state: ' + state);
      }
    });

    p.on('timeUpdate', (ms: number): void => {
      // A stale video's leftover timeUpdate would drive correctDrift to seek
      // the CURRENT video's track against an unrelated timeline → stutter.
      if (p !== this.videoPlayer) {
        return;
      }
      this.channel?.invokeMethod('onPosition', ms);
      this.correctDrift(ms);
      // Update AVSession playback position for notification progress bar.
      this.updateAVPlaybackPosition(ms);
    });

    p.on('durationUpdate', (ms: number): void => {
      if (p !== this.videoPlayer) {
        return;
      }
      this.channel?.invokeMethod('onDuration', ms);
      // Update AVSession duration for notification progress bar.
      this.mediaDurationMs = ms;
      this.updateAVMetadata();
    });

    p.on('bufferingUpdate', (
      infoType: media.BufferingInfoType,
      value: number,
    ): void => {
      if (p !== this.videoPlayer) {
        return;
      }
      if (infoType === media.BufferingInfoType.BUFFERING_START) {
        this.channel?.invokeMethod('onBuffering', true);
      } else if (infoType === media.BufferingInfoType.BUFFERING_END) {
        this.channel?.invokeMethod('onBuffering', false);
      } else if (infoType === media.BufferingInfoType.CACHED_DURATION) {
        this.channel?.invokeMethod('onBuffered', value);
      }
    });

    p.on('error', (err: BusinessError): void => {
      if (p !== this.videoPlayer) {
        return;
      }
      Log.e(TAG, 'video error: ' + JSON.stringify(err));
      this.channel?.invokeMethod('onError', '视频轨错误: ' + err.message);
    });
  }

  private bindAudioEvents(p: media.AVPlayer): void {
    p.on('stateChange', (state: string): void => {
      if (p !== this.audioPlayer) {
        return;
      }
      Log.i(TAG, 'audio stateChange: ' + state);
      if (state === 'initialized') {
        p.prepare();
      } else if (state === 'prepared') {
        this.audioReady = true;
        Log.i(TAG, 'audio prepared, audioReady=true, calling maybeStart');
        this.maybeStart();
      }
    });
    p.on('error', (err: BusinessError): void => {
      if (p !== this.audioPlayer) {
        return;
      }
      Log.e(TAG, 'audio error: ' + JSON.stringify(err));
      this.channel?.invokeMethod('onError', '音频轨错误: ' + err.message);
    });
  }

  // -------------------------------------------------------------------------
  // Playback control
  // -------------------------------------------------------------------------
  private maybeStart(): void {
    if (!(this.videoReady && this.audioReady)) {
      Log.i(TAG, 'maybeStart: videoReady=' + this.videoReady + ', audioReady=' + this.audioReady + ' (waiting)');
      return;
    }
    Log.i(TAG, 'maybeStart: both ready, wantPlay=' + this.wantPlay + ', startMs=' + this.startMs + ', startSeekDone=' + this.startSeekDone);
    if (!this.startSeekDone && this.startMs > 0) {
      this.startSeekDone = true;
      this.videoPlayer?.seek(this.startMs, media.SeekMode.SEEK_CLOSEST);
      this.audioPlayer?.seek(this.startMs, media.SeekMode.SEEK_CLOSEST);
    }
    this.applySpeed();
    if (this.wantPlay) {
      this.playInternal();
    } else {
      this.channel?.invokeMethod('onPlayingChanged', false);
    }
  }

  private playInternal(): void {
    this.videoPlayer?.play();
    this.audioPlayer?.play();
  }

  private applySpeed(): void {
    // setSpeed is only valid once both tracks are prepared; maybeStart()
    // re-invokes applySpeed() after prepare so the pending speed still lands.
    if (!(this.videoReady && this.audioReady)) {
      return;
    }
    if (this.speed == this.appliedSpeed) {
      return;
    }
    const s = NativeDualPlayer.toPlaybackSpeed(this.speed);
    try {
      this.videoPlayer?.setSpeed(s);
      this.audioPlayer?.setSpeed(s);
      this.appliedSpeed = this.speed;
    } catch (e) {
      Log.e(TAG, 'setSpeed failed: ' + JSON.stringify(e));
    }
  }

  private seekBoth(ms: number): void {
    this.videoPlayer?.seek(ms, media.SeekMode.SEEK_CLOSEST);
    this.audioPlayer?.seek(ms, media.SeekMode.SEEK_CLOSEST);
  }

  private correctDrift(videoMs: number): void {
    if (this.audioPlayer === null) {
      return;
    }
    const audioMs = this.audioPlayer.currentTime;
    if (audioMs < 0 || Math.abs(videoMs - audioMs) <= this.syncThresholdMs) {
      return;
    }
    const now = Date.now();
    if (now - this.lastDriftSeekTs < DRIFT_SEEK_COOLDOWN_MS) {
      return;
    }
    this.lastDriftSeekTs = now;
    if (this.syncMaster === MASTER_VIDEO) {
      this.audioPlayer.seek(videoMs, media.SeekMode.SEEK_CLOSEST);
    } else {
      this.videoPlayer?.seek(audioMs, media.SeekMode.SEEK_CLOSEST);
    }
  }

  // -------------------------------------------------------------------------
  // Teardown
  // -------------------------------------------------------------------------
  private async resetPlayers(): Promise<void> {
    this.videoReady = false;
    this.audioReady = false;
    // Fresh AVPlayers start at 1.0x; force re-apply of the desired speed once
    // the new tracks are prepared.
    this.appliedSpeed = -1;
    const v = this.videoPlayer;
    const a = this.audioPlayer;
    this.videoPlayer = null;
    this.audioPlayer = null;
    if (v !== null) {
      v.off('stateChange');
      v.off('timeUpdate');
      v.off('durationUpdate');
      v.off('bufferingUpdate');
      v.off('error');
      try {
        await v.release();
      } catch (e) {
        Log.e(TAG, 'video release failed: ' + JSON.stringify(e));
      }
    }
    if (a !== null) {
      a.off('stateChange');
      a.off('error');
      try {
        await a.release();
      } catch (e) {
        Log.e(TAG, 'audio release failed: ' + JSON.stringify(e));
      }
    }
    this.closeFds();
  }

  private closeFds(): void {
    for (const f of this.openedFds) {
      try {
        fileIo.closeSync(f.fd);
      } catch (e) {
        Log.w(TAG, 'closeSync fd=' + f.fd + ' failed: ' + JSON.stringify(e));
      }
    }
    this.openedFds = [];
  }

  private releaseAll(): void {
    this.wantPlay = false;
    this.pendingInit = null;
    this.stopBackgroundPlayback();
    // Release cover PixelMap
    if (this.mediaCoverPixelMap !== null) {
      try {
        this.mediaCoverPixelMap.release();
      } catch (_) {}
      this.mediaCoverPixelMap = null;
    }
    // Destroy AVSession on release.
    if (this.avSession !== null) {
      try {
        this.avSession.off('play');
        this.avSession.off('pause');
        this.avSession.off('seek');
        this.avSession.off('fastForward');
        this.avSession.off('rewind');
        this.avSession.destroy();
      } catch (e) {
        Log.e(TAG, 'AVSession destroy failed: ' + JSON.stringify(e));
      }
      this.avSession = null;
    }
    // Invalidate any in-flight/queued setup, then tear down after it settles.
    this.genId++;
    this.runExclusive((): Promise<void> => this.resetPlayers());
  }

  // Convert flutter_ohos's decoded headers (an ES6 Map, or a plain object) into
  // a Record for createMediaSourceWithUrl.
  private static toRecord(value: ESObject): Record<string, string> {
    const out: Record<string, string> = {};
    if (value == null) {
      return out;
    }
    if (value instanceof Map) {
      (value as Map<ESObject, ESObject>).forEach(
        (v: ESObject, k: ESObject): void => {
          out[String(k)] = String(v);
        },
      );
    } else {
      Object.keys(value as object).forEach((k: string): void => {
        out[k] = String((value as Record<string, ESObject>)[k]);
      });
    }
    return out;
  }

  private static toPlaybackSpeed(speed: number): media.PlaybackSpeed {
    if (speed <= 0.75) {
      return media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    } else if (speed <= 1.0) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    } else if (speed <= 1.25) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
    } else if (speed <= 1.75) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_75_X;
    } else {
      return media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
    }
  }

  // -------------------------------------------------------------------------\
  // Background playback (AVSession + long-running task)
  // -------------------------------------------------------------------------\

  // Start AVSession and background long-running task so the app is not
  // suspended when the user switches away while media is playing.
  private startBackgroundPlayback(): void {
    if (this.bgTaskRunning) {
      return;
    }
    const ctx = NativeDualPlayer.abilityContext;
    if (ctx === null) {
      Log.w(TAG, 'startBackgroundPlayback: no ability context');
      return;
    }
    this.bgTaskRunning = true;

    // Create / activate AVSession — required so the system doesn't pause
    // the audio when the app goes to background.
    this.ensureAVSession(ctx);

    // Request a long-running background task so the app isn't suspended.
    this.startBgTask(ctx);
  }

  // Stop AVSession and background long-running task when playback pauses /
  // stops / completes, or the player is released.
  private stopBackgroundPlayback(): void {
    if (!this.bgTaskRunning) {
      return;
    }
    this.bgTaskRunning = false;

    // Deactivate AVSession.
    if (this.avSession !== null) {
      try {
        this.avSession.deactivate();
      } catch (e) {
        Log.e(TAG, 'AVSession deactivate failed: ' + JSON.stringify(e));
      }
    }

    // Cancel the long-running background task.
    const ctx = NativeDualPlayer.abilityContext;
    if (ctx !== null) {
      backgroundTaskManager.stopBackgroundRunning(ctx).catch((e: BusinessError): void => {
        Log.e(TAG, 'stopBackgroundRunning failed: ' + JSON.stringify(e));
      });
    }
  }

  private async ensureAVSession(ctx: common.UIAbilityContext): Promise<void> {
    if (this.avSession !== null) {
      try {
        this.avSession.activate();
      } catch (e) {
        Log.e(TAG, 'AVSession activate failed: ' + JSON.stringify(e));
      }
      return;
    }
    try {
      this.avSession = await avSession.createAVSession(ctx, 'PiliPlusVideo', 'video');
      this.avSession.activate();
      // Register media control callbacks so the notification bar play/pause/seek
      // buttons can control the player.
      this.avSession.on('play', (): void => {
        Log.i(TAG, 'AVSession: play command');
        this.wantPlay = true;
        if (this.videoReady && this.audioReady) {
          this.playInternal();
        }
      });
      this.avSession.on('pause', (): void => {
        Log.i(TAG, 'AVSession: pause command');
        this.wantPlay = false;
        this.videoPlayer?.pause();
        this.audioPlayer?.pause();
      });
      this.avSession.on('seek', (ms: number): void => {
        Log.i(TAG, 'AVSession: seek command ms=' + ms);
        this.seekBoth(ms);
      });
      this.avSession.on('fastForward', (): void => {
        Log.i(TAG, 'AVSession: fastForward command');
        this.seekBoth(Math.min(
          (this.videoPlayer?.currentTime ?? 0) + 10000,
          this.mediaDurationMs,
        ));
      });
      this.avSession.on('rewind', (): void => {
        Log.i(TAG, 'AVSession: rewind command');
        this.seekBoth(Math.max(
          (this.videoPlayer?.currentTime ?? 0) - 10000,
          0,
        ));
      });
      // Set initial metadata & playback state on the AVSession.
      this.updateAVMetadata();
      this.updateAVPlaybackState('paused', 0, 1.0, 0);
      Log.i(TAG, 'AVSession created and activated');
    } catch (e) {
      Log.e(TAG, 'createAVSession failed: ' + JSON.stringify(e));
      this.avSession = null;
    }
  }

  /**
   * Update the media metadata shown in the notification bar (title, artist,
   * cover image, duration, live flag).
   */
  private updateAVMetadata(): void {
    if (this.avSession === null) {
      return;
    }
    try {
      const metadata: avSession.AVMetadata = {
        assetId: '1',
        title: this.mediaTitle || 'PiliPlus',
        artist: this.mediaArtist || '',
        mediaImage: this.mediaCoverPixelMap ?? (this.mediaCoverUri || ''),
        duration: this.mediaDurationMs,
      };
      this.avSession.setAVMetadata(metadata);
    } catch (e) {
      Log.e(TAG, 'setAVMetadata failed: ' + JSON.stringify(e));
    }
  }

  /**
   * Update the playback state shown in the notification bar (play/pause icon,
   * progress bar, speed, buffered position).
   */
  private updateAVPlaybackState(stateStr: string, posMs: number, speed: number, bufferedMs: number): void {
    if (this.avSession === null) {
      return;
    }
    try {
      let state: avSession.PlaybackState = avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
      switch (stateStr) {
        case 'playing':
          state = avSession.PlaybackState.PLAYBACK_STATE_PLAY;
          break;
        case 'paused':
          state = avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
          break;
        case 'buffering':
          state = avSession.PlaybackState.PLAYBACK_STATE_BUFFERING;
          break;
        case 'completed':
          state = avSession.PlaybackState.PLAYBACK_STATE_COMPLETED;
          break;
        case 'stopped':
          state = avSession.PlaybackState.PLAYBACK_STATE_STOP;
          break;
        default:
          break;
      }
      const playbackState: avSession.AVPlaybackState = {
        state: state,
        position: {
          elapsedTime: posMs,
          updateTime: Date.now(),
        },
        speed: speed,
        bufferedTime: bufferedMs,
        duration: this.mediaDurationMs,
      };
      this.avSession.setAVPlaybackState(playbackState);
    } catch (e) {
      Log.e(TAG, 'setAVPlaybackState failed: ' + JSON.stringify(e));
    }
  }

  /**
   * Lightweight position-only update for the notification bar progress bar.
   * Called from the timeUpdate callback to keep the progress bar smooth.
   */
  private updateAVPlaybackPosition(ms: number): void {
    if (this.avSession === null) {
      return;
    }
    try {
      const playbackState: avSession.AVPlaybackState = {
        state: this.wantPlay ?
          avSession.PlaybackState.PLAYBACK_STATE_PLAY :
          avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        position: {
          elapsedTime: ms,
          updateTime: Date.now(),
        },
        speed: this.videoPlayer?.state === 'playing' ? this.speed : 1.0,
        duration: this.mediaDurationMs,
      };
      this.avSession.setAVPlaybackState(playbackState);
    } catch (e) {
      // Silently ignore — this is called frequently from timeUpdate.
    }
  }

  private async startBgTask(ctx: common.UIAbilityContext): Promise<void> {
    try {
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: ctx.abilityInfo.bundleName,
            abilityName: ctx.abilityInfo.name,
          },
        ],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      };
      const agent = await wantAgent.getWantAgent(wantAgentInfo);
      await backgroundTaskManager.startBackgroundRunning(ctx, backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, agent);
      Log.i(TAG, 'startBackgroundRunning succeeded');
    } catch (e) {
      Log.e(TAG, 'startBackgroundRunning failed: ' + JSON.stringify(e));
    }
  }

  /**
   * Download cover image from network and create PixelMap for AVSession metadata.
   * Falls back to URI string if download fails.
   */
  private async loadCoverImage(url: string): Promise<void> {
    if (!url || url.length === 0) {
      return;
    }
    try {
      const httpClient = http.createHttp();
      const response = await httpClient.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 8000,
        readTimeout: 8000,
      });
      httpClient.destroy();
      if (response.responseCode !== 200 || !response.result) {
        Log.w(TAG, 'loadCoverImage: HTTP ' + response.responseCode + ' for ' + url);
        return;
      }
      const buf = response.result as ArrayBuffer;
      const imageSource = image.createImageSource(buf);
      const pixelMap = await imageSource.createPixelMap();
      // Release old PixelMap if any
      if (this.mediaCoverPixelMap !== null) {
        try {
          this.mediaCoverPixelMap.release();
        } catch (_) {}
      }
      this.mediaCoverPixelMap = pixelMap;
      // Re-set metadata with the PixelMap
      this.updateAVMetadata();
      Log.i(TAG, 'loadCoverImage: cover PixelMap loaded successfully');
    } catch (e) {
      Log.e(TAG, 'loadCoverImage failed: ' + JSON.stringify(e));
    }
  }
}
