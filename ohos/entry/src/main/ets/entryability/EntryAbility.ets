
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import MediaKitVideoPlugin from '../plugins/MediaKitVideoPlugin';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // Registered here (not in GeneratedPluginRegistrant) because the Flutter
    // tool regenerates GeneratedPluginRegistrant.ets on every build and would
    // drop this hand-written plugin.
    flutterEngine.getPlugins()?.add(new MediaKitVideoPlugin())
  }
}
