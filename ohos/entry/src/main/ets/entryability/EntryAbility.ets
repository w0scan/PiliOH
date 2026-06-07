
import {
  FlutterAbility,
  FlutterEngine,
  Log,
  MethodCall,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import window from '@ohos.window';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import MediaKitVideoPlugin from '../plugins/MediaKitVideoPlugin';
import NativeDualPlayer from '../plugins/NativeDualPlayer';
import PiPManager from '../plugins/PiPManager';
import FilePickerOhos from '../plugins/FilePickerOhos';

const TAG = 'EntryAbility';

export default class EntryAbility extends FlutterAbility {
  private mainWin: window.Window | null = null;
  private wakelockChannel: MethodChannel | null = null;
  private pipChannel: MethodChannel | null = null;
  // Desired keep-screen-on state. Cached so we can (re)apply it once the
  // window exists, and answer the isEnabled query.
  private keepScreenOn: boolean = false;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // Registered here (not in GeneratedPluginRegistrant) because the Flutter
    // tool regenerates GeneratedPluginRegistrant.ets on every build and would
    // drop this hand-written plugin.
    flutterEngine.getPlugins()?.add(new MediaKitVideoPlugin())
    // Native dual-AVPlayer (OHOS-only alternative player). Registered here for
    // the same reason as MediaKitVideoPlugin: GeneratedPluginRegistrant is
    // regenerated each build and would drop a hand-written plugin.
    flutterEngine.getPlugins()?.add(new NativeDualPlayer())

    // wakelock_plus has no ohos implementation; the Dart side (OhosWakelock)
    // talks to this channel so video playback can keep the screen awake.
    this.wakelockChannel = new MethodChannel(
      flutterEngine.getDartExecutor(),
      'piliplus/wakelock',
    );
    this.wakelockChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        switch (call.method) {
          case 'toggle':
            this.keepScreenOn = call.args as boolean;
            this.applyKeepScreenOn();
            result.success(null);
            break;
          case 'isEnabled':
            result.success(this.keepScreenOn);
            break;
          default:
            result.notImplemented();
        }
      },
    });

    // OpenHarmony Picture-in-Picture. The Dart side (OhosPipHelper) passes the
    // mpv core handle (decimal string) so the native render output can be
    // rebound onto the PiP window surface and back.
    this.pipChannel = new MethodChannel(
      flutterEngine.getDartExecutor(),
      'piliplus/pip',
    );
    PiPManager.getInstance().setChannel(this.pipChannel);
    this.pipChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        switch (call.method) {
          case 'isSupported':
            result.success(PiPManager.getInstance().isSupported());
            break;
          case 'enter': {
            const handle = call.argument('handle') as string;
            const width = call.argument('width') as number;
            const height = call.argument('height') as number;
            const autoStart = call.argument('autoStart') as boolean;
            const isPlaying = call.argument('isPlaying') as boolean;
            PiPManager.getInstance()
              .enter(handle, width, height, autoStart === true, isPlaying !== false)
              .then((): void => result.success(true))
              .catch((e: Object): void => {
                Log.e(TAG, 'pip enter failed: ' + JSON.stringify(e));
                result.success(false);
              });
            break;
          }
          case 'exit':
            PiPManager.getInstance()
              .exit()
              .then((): void => result.success(null))
              .catch((): void => result.success(null));
            break;
          case 'setAutoStart':
            PiPManager.getInstance().setAutoStart(call.args as boolean);
            result.success(null);
            break;
          case 'setPlaybackState':
            PiPManager.getInstance().setPlaybackState(call.args as boolean);
            result.success(null);
            break;
          case 'updateContentSize': {
            const width = call.argument('width') as number;
            const height = call.argument('height') as number;
            PiPManager.getInstance().updateContentSize(width, height);
            result.success(null);
            break;
          }
          default:
            result.notImplemented();
        }
      },
    });

    // OpenHarmony file picker (save/import). The Dart side (OhosFilePicker)
    // talks to this channel so export/import can use native system dialogs.
    const filePickerChannel = new MethodChannel(
      flutterEngine.getDartExecutor(),
      'piliplus/file_picker',
    );
    filePickerChannel.setMethodCallHandler({
      onMethodCall: (call: MethodCall, result: MethodResult): void => {
        FilePickerOhos.handleCall(call, result);
      },
    });
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    super.onWindowStageCreate(windowStage)
    const mainWin = windowStage.getMainWindowSync();
    this.mainWin = mainWin;
    // Re-apply in case a toggle arrived before the window was ready.
    this.applyKeepScreenOn();
    // PiPWindow.create needs an ability context + a UIContext to build the
    // content XComponent node. The UIContext isn't ready yet here (Flutter
    // hasn't finished loadContent), so PiPManager resolves it lazily from the
    // window on first use.
    PiPManager.getInstance().setContext(this.context, mainWin);
  }

  private applyKeepScreenOn(): void {
    this.mainWin?.setWindowKeepScreenOn(this.keepScreenOn)
      .catch((e: Object): void => {
        Log.e(TAG, 'setWindowKeepScreenOn failed: ' + JSON.stringify(e));
      });
  }
}
