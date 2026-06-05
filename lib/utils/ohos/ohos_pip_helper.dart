import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// OpenHarmony Picture-in-Picture bridge.
///
/// HarmonyOS has no media_kit/Flutter PiP plugin, so the native EntryAbility
/// exposes a lightweight MethodChannel that drives `@ohos.PiPWindow`. The mpv
/// video output (rendered by the `media_kit_ohos_video` C++ module) is rebound
/// onto the PiP window surface and back to the Flutter texture by the native
/// side; here we only forward intent + the mpv core handle.
abstract final class OhosPipHelper {
  static const MethodChannel _channel = MethodChannel('piliplus/pip');

  /// Whether the current device/OS supports PiP. Cached after the first query.
  static bool? _supported;

  /// True while a native PiP window is active. The player consults this so it
  /// doesn't pause playback when the app goes to background during PiP.
  static final ValueNotifier<bool> isInPip = ValueNotifier<bool>(false);

  /// Invoked when the PiP control-panel play/pause button is tapped; the
  /// argument is the desired playing state. Wired by the player controller.
  static void Function(bool play)? onPlayPause;

  static bool _handlerSet = false;

  static void _ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPipStateChanged':
          isInPip.value = call.arguments == true;
          break;
        case 'onPlayPause':
          onPlayPause?.call(call.arguments == true);
          break;
      }
      return null;
    });
  }

  static Future<bool> isSupported() async {
    if (_supported != null) return _supported!;
    try {
      _supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      _supported = false;
    }
    return _supported!;
  }

  /// Enter PiP for the mpv core identified by [handle] (the `player.handle`
  /// address). [width]/[height] are the source video dimensions for the PiP
  /// aspect ratio. When [autoStart] is true the system auto-starts PiP on
  /// returning home.
  static Future<bool> enterPip({
    required int handle,
    required int width,
    required int height,
    bool autoStart = false,
    bool isPlaying = true,
  }) async {
    _ensureHandler();
    try {
      final ok = await _channel.invokeMethod<bool>('enter', {
        'handle': handle.toString(),
        'width': width,
        'height': height,
        'autoStart': autoStart,
        'isPlaying': isPlaying,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> exitPip() async {
    try {
      await _channel.invokeMethod<void>('exit');
    } catch (_) {}
  }

  /// Enable/disable auto-start of PiP when the app goes to background.
  static Future<void> setAutoStart(bool enable) async {
    try {
      await _channel.invokeMethod<void>('setAutoStart', enable);
    } catch (_) {}
  }

  /// Push the player's current play/pause state so the PiP control-panel icon
  /// stays in sync.
  static Future<void> setPlaybackState(bool playing) async {
    try {
      await _channel.invokeMethod<void>('setPlaybackState', playing);
    } catch (_) {}
  }

  static Future<void> updateContentSize(int width, int height) async {
    try {
      await _channel.invokeMethod<void>('updateContentSize', {
        'width': width,
        'height': height,
      });
    } catch (_) {}
  }
}
