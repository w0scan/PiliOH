import PiPWindow from '@ohos.PiPWindow';
import window from '@ohos.window';
import { typeNode } from '@ohos.arkui.node';
import type { UIContext } from '@ohos.arkui.UIContext';
import type common from '@ohos.app.ability.common';
import type { BusinessError } from '@ohos.base';
import { Log, MethodChannel } from '@ohos/flutter_ohos';
import mpvVideo from 'libmedia_kit_ohos_video.so';

const TAG = 'PiPManager';

// XComponentController whose surface lifecycle is forwarded to PiPManager so the
// native mpv render output can be rebound onto / away from the PiP surface.
//
// The PiP window owns an XComponent (SURFACE type). When PiP starts the system
// creates that surface and calls onSurfaceCreated; we hand its surface id to the
// native module so the *same* mpv render context starts drawing into the PiP
// window. When PiP stops the surface is destroyed and we rebind back to the
// Flutter texture so inline playback resumes.
class PiPXComponentController extends XComponentController {
  onSurfaceCreated(surfaceId: string): void {
    Log.i(TAG, 'pip surface created: ' + surfaceId);
    // Route through the singleton rather than a captured `owner` field: when the
    // system invokes this callback, subclass instance fields are not reliably
    // initialized (ArkTS native-extend quirk), so `this.owner` came back
    // undefined and crashed the app.
    PiPManager.getInstance().onPipSurfaceCreated(surfaceId);
  }

  onSurfaceDestroyed(surfaceId: string): void {
    Log.i(TAG, 'pip surface destroyed: ' + surfaceId);
    PiPManager.getInstance().onPipSurfaceDestroyed();
  }
}

// Drives OpenHarmony Picture-in-Picture for the media_kit mpv video output.
//
// One PiP window at a time (matching the single active player). The mpv core is
// identified by its handle (the mpv_handle* address, passed from Dart as a
// decimal string). Rendering is moved between the Flutter texture and the PiP
// XComponent surface by the native `media_kit_ohos_video` module via rebind.
export default class PiPManager {
  private static instance: PiPManager | null = null;

  static getInstance(): PiPManager {
    if (PiPManager.instance == null) {
      PiPManager.instance = new PiPManager();
    }
    return PiPManager.instance;
  }

  private context: common.BaseContext | null = null;
  private mainWindow: window.Window | null = null;
  private uiContext: UIContext | null = null;

  // Channel back to Dart (piliplus/pip). Used to (a) tell the player it is now
  // in PiP so it shouldn't pause on background, and (b) forward control-panel
  // play/pause taps so the player toggles.
  private channel: MethodChannel | null = null;

  private controller: PiPWindow.PiPController | null = null;
  private xcomponentController: PiPXComponentController | null = null;
  private contentNode: typeNode.XComponent | null = null;

  // The mpv handle currently bound to the PiP window (decimal string), or null
  // when no PiP session is active.
  private activeHandle: string | null = null;
  // True once we have rebound mpv onto the PiP surface; guards the rebind-back.
  private boundToPip: boolean = false;
  // Last known playback state pushed from Dart, so the control panel icon stays
  // in sync. true = playing.
  private playing: boolean = true;

  setChannel(channel: MethodChannel): void {
    this.channel = channel;
  }

  // Supplied once by EntryAbility when the window stage is ready. The UIContext
  // is resolved lazily (see resolveUiContext) because at onWindowStageCreate
  // time Flutter has not finished loadContent yet, so getUIContext() returns
  // null until the first frame is up.
  setContext(context: common.BaseContext, mainWindow: window.Window): void {
    this.context = context;
    this.mainWindow = mainWindow;
  }

  // Returns a usable UIContext or null, caching it once available.
  private resolveUiContext(): UIContext | null {
    if (this.uiContext != null) {
      return this.uiContext;
    }
    if (this.mainWindow == null) {
      return null;
    }
    try {
      const ctx = this.mainWindow.getUIContext();
      if (ctx != null) {
        this.uiContext = ctx;
      }
      return this.uiContext;
    } catch (e) {
      Log.e(TAG, 'getUIContext failed: ' + JSON.stringify(e));
      return null;
    }
  }

  isSupported(): boolean {
    try {
      return PiPWindow.isPiPEnabled();
    } catch (e) {
      Log.e(TAG, 'isPiPEnabled failed: ' + JSON.stringify(e));
      return false;
    }
  }

  // Start (or restart) a PiP session for the given mpv handle. width/height are
  // the source video dimensions, used for the PiP aspect ratio.
  async enter(
    handle: string,
    width: number,
    height: number,
    autoStart: boolean,
    isPlaying: boolean,
  ): Promise<void> {
    this.playing = isPlaying;
    if (this.context == null) {
      Log.e(TAG, 'enter: no context');
      return;
    }
    const uiContext = this.resolveUiContext();
    if (uiContext == null) {
      Log.e(TAG, 'enter: no UIContext (window not ready)');
      return;
    }
    if (!this.isSupported()) {
      Log.e(TAG, 'enter: PiP not supported on this device');
      return;
    }

    // If a session is already live, just (re)bind it to the new handle/size.
    if (this.controller != null) {
      this.activeHandle = handle;
      this.updateContentSize(width, height);
      try {
        await this.controller.startPiP();
      } catch (e) {
        Log.e(TAG, 'restart startPiP failed: ' + JSON.stringify(e));
      }
      return;
    }

    this.activeHandle = handle;
    this.boundToPip = false;

    const w: number = width > 0 ? width : 16;
    const h: number = height > 0 ? height : 9;

    this.xcomponentController = new PiPXComponentController();
    const options: XComponentOptions = {
      type: XComponentType.SURFACE,
      controller: this.xcomponentController,
    };
    this.contentNode = typeNode.createNode(
      uiContext,
      'XComponent',
      options,
    );

    const config: PiPWindow.PiPConfiguration = {
      context: this.context,
      componentController: this.xcomponentController,
      templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
      contentWidth: w,
      contentHeight: h,
    };

    try {
      this.controller = await PiPWindow.create(config, this.contentNode);
    } catch (e) {
      Log.e(TAG, 'PiPWindow.create failed: ' + JSON.stringify(e));
      this.cleanup();
      return;
    }

    this.controller.on('stateChange', (state: PiPWindow.PiPState, reason: string): void => {
      this.onStateChange(state, reason);
    });

    // The control-panel play/pause button. The system sends
    // 'playbackStateChanged' with status 1 (-> should play) / 0 (-> should
    // pause); we forward the desired state to Dart, which drives the player.
    this.controller.on(
      'controlPanelActionEvent',
      (event: PiPWindow.PiPActionEventType, status?: number): void => {
        Log.i(TAG, 'controlPanelActionEvent: ' + event + ' status=' + status);
        if (event === 'playbackStateChanged') {
          const shouldPlay: boolean = status === 1;
          this.channel?.invokeMethod('onPlayPause', shouldPlay);
        }
      },
    );

    if (autoStart) {
      this.controller.setAutoStartEnabled(true);
    }

    try {
      await this.controller.startPiP();
    } catch (e) {
      Log.e(TAG, 'startPiP failed: ' + JSON.stringify(e));
    }
  }

  // Stop the active PiP session (returns rendering to the Flutter texture).
  async exit(): Promise<void> {
    if (this.controller == null) {
      return;
    }
    try {
      await this.controller.stopPiP();
    } catch (e) {
      Log.e(TAG, 'stopPiP failed: ' + JSON.stringify(e));
    }
  }

  setAutoStart(enable: boolean): void {
    this.controller?.setAutoStartEnabled(enable);
  }

  // Pushed from Dart whenever the player's play/pause state changes, so the PiP
  // control-panel icon reflects reality.
  setPlaybackState(playing: boolean): void {
    this.playing = playing;
    try {
      this.controller?.updatePiPControlStatus(
        PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE,
        playing
          ? PiPWindow.PiPControlStatus.PLAY
          : PiPWindow.PiPControlStatus.PAUSE,
      );
    } catch (e) {
      Log.e(TAG, 'updatePiPControlStatus failed: ' + JSON.stringify(e));
    }
  }

  updateContentSize(width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    this.controller?.updateContentSize(width, height);
  }

  // ----- surface lifecycle (called by PiPXComponentController) -----

  onPipSurfaceCreated(surfaceId: string): void {
    if (this.activeHandle == null) {
      return;
    }
    try {
      mpvVideo.rebind(BigInt(this.activeHandle), BigInt(surfaceId));
      this.boundToPip = true;
    } catch (e) {
      Log.e(TAG, 'rebind to pip failed: ' + JSON.stringify(e));
    }
  }

  onPipSurfaceDestroyed(): void {
    this.rebindToFlutter();
  }

  // ----- internals -----

  private rebindToFlutter(): void {
    if (this.activeHandle == null || !this.boundToPip) {
      return;
    }
    try {
      mpvVideo.rebindToFlutter(BigInt(this.activeHandle));
    } catch (e) {
      Log.e(TAG, 'rebindToFlutter failed: ' + JSON.stringify(e));
    }
    this.boundToPip = false;
  }

  private onStateChange(state: PiPWindow.PiPState, reason: string): void {
    Log.i(TAG, 'pip state=' + state + ' reason=' + reason);
    switch (state) {
      case PiPWindow.PiPState.STARTED:
        // Tell Dart we're in PiP so it won't pause playback on background, and
        // sync the initial control-panel icon.
        this.channel?.invokeMethod('onPipStateChanged', true);
        this.setPlaybackState(this.playing);
        break;
      case PiPWindow.PiPState.STOPPED:
      case PiPWindow.PiPState.ERROR:
        // Make sure mpv is drawing into the Flutter texture again, then drop
        // the controller so a later enter() rebuilds a fresh window.
        this.channel?.invokeMethod('onPipStateChanged', false);
        this.rebindToFlutter();
        this.cleanup();
        break;
      default:
        break;
    }
  }

  private cleanup(): void {
    if (this.controller != null) {
      try {
        this.controller.off('stateChange');
      } catch (e) {
        Log.e(TAG, 'off stateChange failed: ' + JSON.stringify(e));
      }
    }
    this.controller = null;
    this.contentNode = null;
    this.xcomponentController = null;
    this.activeHandle = null;
    this.boundToPip = false;
  }
}
