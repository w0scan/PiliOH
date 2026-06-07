import 'package:flutter/services.dart';

/// OpenHarmony native dual-AVPlayer bridge.
///
/// On OHOS the app can optionally play DASH video with two native
/// `@ohos.multimedia.media` AVPlayer instances (one audio, one video) instead
/// of media_kit/mpv. The video player renders into a Flutter texture (bound on
/// the native side via the NDK `OH_AVPlayer_SetVideoSurface` against the
/// texture's OHNativeWindow, mirroring `media_kit_ohos_video`). This Dart side
/// drives source/lifecycle over the `piliplus/native_player` MethodChannel and
/// receives position/duration/buffer/state callbacks.
abstract final class OhosNativePlayer {
  static const MethodChannel _channel = MethodChannel('piliplus/native_player');

  /// Position (ms) of the sync master track, pushed from native.
  static void Function(int positionMs)? onPosition;

  /// Total duration (ms) once prepared.
  static void Function(int durationMs)? onDuration;

  /// Buffered position (ms) of the video track.
  static void Function(int bufferedMs)? onBuffered;

  /// Playing/paused state changes originating natively (e.g. focus loss).
  static void Function(bool playing)? onPlayingChanged;

  /// Buffering (stall) state.
  static void Function(bool buffering)? onBuffering;

  /// Playback reached the end.
  static void Function()? onCompleted;

  /// Fatal player error; argument is a human-readable message.
  static void Function(String message)? onError;

  /// Decoded video pixel dimensions, once known.
  static void Function(int width, int height)? onVideoSize;

  static bool _handlerSet = false;

  static void _ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPosition':
          onPosition?.call((call.arguments as num).toInt());
        case 'onDuration':
          onDuration?.call((call.arguments as num).toInt());
        case 'onBuffered':
          onBuffered?.call((call.arguments as num).toInt());
        case 'onPlayingChanged':
          onPlayingChanged?.call(call.arguments == true);
        case 'onBuffering':
          onBuffering?.call(call.arguments == true);
        case 'onCompleted':
          onCompleted?.call();
        case 'onError':
          onError?.call(call.arguments?.toString() ?? '');
        case 'onVideoSize':
          final args = call.arguments;
          onVideoSize?.call(
            (args['w'] as num).toInt(),
            (args['h'] as num).toInt(),
          );
      }
      return null;
    });
  }

  /// Create the native players + a Flutter texture for the video output.
  /// Returns the textureId to display via a [Texture] widget, or null on
  /// failure.
  static Future<int?> create() async {
    _ensureHandler();
    try {
      return await _channel.invokeMethod<int>('create');
    } catch (_) {
      return null;
    }
  }

  /// Set (or replace) the playing sources. [audioUrl] may be null/empty to play
  /// video-only or audio-only (when [videoUrl] is the audio for audio-only).
  /// [headers] carries referer/user-agent for B站 streams. [startMs] is the
  /// initial seek position.
  static Future<void> setSource({
    required String videoUrl,
    String? audioUrl,
    required Map<String, String> headers,
    int startMs = 0,
    int syncMaster = 0,
    int syncThresholdMs = 2000,
    int width = 0,
    int height = 0,
  }) async {
    // Ensure the native->Dart callback handler is registered (in PlatformView
    // mode there's no create() call to do it).
    _ensureHandler();
    try {
      await _channel.invokeMethod<void>('setSource', {
        'videoUrl': videoUrl,
        'audioUrl': audioUrl,
        'headers': headers,
        'startMs': startMs,
        'syncMaster': syncMaster,
        'syncThresholdMs': syncThresholdMs,
        'width': width,
        'height': height,
      });
    } catch (_) {}
  }

  static Future<void> play() => _invoke('play');
  static Future<void> pause() => _invoke('pause');
  static Future<void> release() => _invoke('release');

  static Future<void> seek(int positionMs) async {
    try {
      await _channel.invokeMethod<void>('seek', positionMs);
    } catch (_) {}
  }

  static Future<void> setSpeed(double speed) async {
    try {
      await _channel.invokeMethod<void>('setSpeed', speed);
    } catch (_) {}
  }

  static Future<void> setVolume(double volume) async {
    try {
      await _channel.invokeMethod<void>('setVolume', volume);
    } catch (_) {}
  }

  /// Switch the sync master track at runtime (0 = audio, 1 = video).
  static Future<void> setSyncMaster(int master) async {
    try {
      await _channel.invokeMethod<void>('setSyncMaster', master);
    } catch (_) {}
  }

  /// Change the drift threshold (ms) at runtime.
  static Future<void> setSyncThreshold(int thresholdMs) async {
    try {
      await _channel.invokeMethod<void>('setSyncThreshold', thresholdMs);
    } catch (_) {}
  }

  static Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {}
  }
}
