import 'package:flutter/services.dart';

/// OpenHarmony external URL launcher bridge.
///
/// On OHOS the `url_launcher` package has no platform implementation, so
/// calling it throws MissingPluginException. This lightweight MethodChannel
/// drives a native `startAbility` with the browsable action so links open in
/// the system browser / matching app. On other platforms, use url_launcher.
abstract final class OhosLauncher {
  static const MethodChannel _channel = MethodChannel('piliplus/launcher');

  /// Open [url] externally. Returns true if the native side launched it.
  static Future<bool> launchUrl(String url) async {
    try {
      final ok = await _channel.invokeMethod<bool>('launchUrl', url);
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
