
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

const TAG = 'EntryAbility';

export default class EntryAbility extends FlutterAbility {
  private mainWin: window.Window | null = null;
  private wakelockChannel: MethodChannel | null = null;
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
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    super.onWindowStageCreate(windowStage)
    this.mainWin = windowStage.getMainWindowSync();
    // Re-apply in case a toggle arrived before the window was ready.
    this.applyKeepScreenOn();
  }

  private applyKeepScreenOn(): void {
    this.mainWin?.setWindowKeepScreenOn(this.keepScreenOn)
      .catch((e: Object): void => {
        Log.e(TAG, 'setWindowKeepScreenOn failed: ' + JSON.stringify(e));
      });
  }
}
