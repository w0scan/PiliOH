import media from '@ohos.multimedia.media';
import fileIo from '@ohos.file.fs';
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

  // Video dimensions (updated on prepared / widthUpdate), used to calculate
  // letterbox surface rect so the video isn't stretched on fullscreen.
  private videoWidth: number = 0;
  private videoHeight: number = 0;

  // Reference to the PlatformView factory so we can reach the current
  // NativePlayerView and call setXComponentSurfaceRect on its controller.
  private viewFactory: NativePlayerViewFactory | null = null;

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
    this.viewFactory = factory;
    Log.i(TAG, 'attached');
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
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
        // Re-apply letterbox surface rect after surface rebinding.
        this.refreshSurfaceRect();
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

  // Called by NativePlayerView when the XComponent layout area changes
  // (e.g. fullscreen toggle).  Recalculates the letterbox surface rect so
  // the video keeps its aspect ratio instead of being stretched.
  updateSurfaceRect(containerWidth: number, containerHeight: number): void {
    if (this.videoWidth <= 0 || this.videoHeight <= 0) {
      return;
    }
    const view = this.viewFactory?.currentView;
    if (view === null || view === undefined) {
      return;
    }
    this.applySurfaceRect(view, containerWidth, containerHeight);
  }

  // Recalculate and apply the letterbox surface rect using the current
  // container dimensions (from the NativePlayerView's cached area).
  refreshSurfaceRect(): void {
    if (this.videoWidth <= 0 || this.videoHeight <= 0) {
      return;
    }
    const view = this.viewFactory?.currentView;
    if (view === null || view === undefined) {
      return;
    }
    const cw = view.containerWidth;
    const ch = view.containerHeight;
    if (cw <= 0 || ch <= 0) {
      return;
    }
    this.applySurfaceRect(view, cw, ch);
  }

  private applySurfaceRect(view: NativePlayerView, cw: number, ch: number): void {
    const vw = this.videoWidth;
    const vh = this.videoHeight;
    // Calculate letterbox rect: fit the video inside the container while
    // preserving aspect ratio, centering the result.
    const videoRatio = vw / vh;
    const containerRatio = cw / ch;
    let surfaceWidth: number;
    let surfaceHeight: number;
    let offsetX: number = 0;
    let offsetY: number = 0;
    if (videoRatio > containerRatio) {
      // Video wider than container → fit width, letterbox top/bottom
      surfaceWidth = cw;
      surfaceHeight = cw / videoRatio;
      offsetY = (ch - surfaceHeight) / 2;
    } else {
      // Video taller than container → fit height, pillarbox left/right
      surfaceHeight = ch;
      surfaceWidth = ch * videoRatio;
      offsetX = (cw - surfaceWidth) / 2;
    }
    const rect: SurfaceRect = {
      offsetX: Math.round(offsetX),
      offsetY: Math.round(offsetY),
      surfaceWidth: Math.round(surfaceWidth),
      surfaceHeight: Math.round(surfaceHeight),
    };
    Log.i(TAG, 'applySurfaceRect: container=' + cw + 'x' + ch +
      ', video=' + vw + 'x' + vh +
      ', rect=' + JSON.stringify(rect));
    try {
      view.xController.setXComponentSurfaceRect(rect);
    } catch (e) {
      Log.e(TAG, 'setXComponentSurfaceRect failed: ' + JSON.stringify(e));
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
          // Now that we know the video size, apply letterbox surface rect.
          this.refreshSurfaceRect();
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
      } else if (state === 'paused') {
        Log.i(TAG, 'video paused → onPlayingChanged(false)');
        this.channel?.invokeMethod('onPlayingChanged', false);
      } else if (state === 'completed') {
        Log.i(TAG, 'video completed → onCompleted');
        this.channel?.invokeMethod('onCompleted', null);
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
    });

    p.on('durationUpdate', (ms: number): void => {
      if (p !== this.videoPlayer) {
        return;
      }
      this.channel?.invokeMethod('onDuration', ms);
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
}
