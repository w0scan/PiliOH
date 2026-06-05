import 'package:flutter/services.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// OpenHarmony implementation of [WakelockPlusPlatformInterface].
///
/// wakelock_plus ships no ohos plugin, so on HarmonyOS the default
/// (Pigeon-based) instance throws and the screen is never kept awake during
/// playback. This routes the same calls to a lightweight MethodChannel that the
/// native EntryAbility handles via window.setWindowKeepScreenOn.
class OhosWakelock extends WakelockPlusPlatformInterface {
  static const MethodChannel _channel = MethodChannel('piliplus/wakelock');

  bool _enabled = false;

  /// Installs this implementation as the platform instance. Must be called
  /// before the first [WakelockPlus] call, because wakelock_plus caches the
  /// instance in a top-level variable on first access.
  static void register() {
    WakelockPlusPlatformInterface.instance = OhosWakelock();
  }

  @override
  Future<void> toggle({required bool enable}) async {
    await _channel.invokeMethod<void>('toggle', enable);
    _enabled = enable;
  }

  @override
  Future<bool> get enabled async => _enabled;
}
