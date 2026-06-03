/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import 'package:media_kit/media_kit.dart';

// ignore_for_file: implementation_imports
import 'package:media_kit/ffi/ffi.dart';

import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

/// {@template ohos_video_controller}
///
/// OhosVideoController
/// -------------------
///
/// The [PlatformVideoController] implementation for OpenHarmony.
///
/// Unlike Android (which uses `--vo=gpu` with `--wid` pointing at an
/// `android.view.Surface`), OpenHarmony's libmpv ships no OS-specific GPU
/// context. So we use the libmpv Render API instead: `--vo=libmpv`, and the
/// native side ([MediaKitVideoPlugin] + the `media_kit_ohos_video` C++ module)
/// attaches an `mpv_render_context` (EGL/OpenGL ES) onto the *same* mpv core
/// that media_kit's Dart [Player] already owns, then pumps frames into a
/// Flutter texture surface. The Dart side only has to:
///   1. set `--vo=libmpv` (+ decode options) before the render context is made,
///   2. ask the native plugin to register a texture & start rendering,
///   3. keep the texture buffer size in sync with the decoded video size.
///
/// {@endtemplate}
class OhosVideoController extends PlatformVideoController {
  /// Whether [OhosVideoController] is supported on the current platform or not.
  static bool get supported => Platform.operatingSystem == 'ohos';

  /// {@macro ohos_video_controller}
  OhosVideoController._(super.player, super.configuration) {
    _subscription = player.stream.videoParams.listen(
      (event) => _lock.synchronized(() async {
        if (const [0, null].contains(event.dw) ||
            const [0, null].contains(event.dh)) {
          return;
        }

        final int width;
        final int height;
        if (event.rotate == 0 || event.rotate == 180) {
          width = event.dw ?? 0;
          height = event.dh ?? 0;
        } else {
          // width & height are swapped for 90 or 270 degrees rotation.
          width = event.dh ?? 0;
          height = event.dw ?? 0;
        }

        rect.value = Rect.zero;
        try {
          await _channel
              .invokeMethod('VideoOutputManager.SetSurfaceTextureSize', {
                'handle': player.handle.toString(),
                'width': width.toString(),
                'height': height.toString(),
              });
        } catch (exception, stacktrace) {
          debugPrint(exception.toString());
          debugPrint(stacktrace.toString());
        }
        rect.value = Rect.fromLTRB(
          0.0,
          0.0,
          width.toDouble(),
          height.toDouble(),
        );

        if (!waitUntilFirstFrameRenderedCompleter.isCompleted) {
          waitUntilFirstFrameRenderedCompleter.complete();
        }
      }),
    );
  }

  /// {@macro ohos_video_controller}
  static Future<PlatformVideoController> create(
    Player player,
    VideoControllerConfiguration configuration,
  ) async {
    // Retrieve the native handle of the [Player].
    final handle = player.handle;
    // Return the existing [VideoController] if it's already created.
    if (_controllers.containsKey(handle)) {
      return _controllers[handle]!;
    }

    // Creation:
    final controller = OhosVideoController._(player, configuration);

    // Register [_dispose] for execution upon [Player.dispose].
    player.release.add(controller._dispose);

    // Store the [VideoController] in the [_controllers].
    _controllers[handle] = controller;

    // Configure the mpv core for Render API output BEFORE the native side
    // creates the render context (mpv requires vo=libmpv to be set first).
    final values = {
      'vo': 'libmpv',
      'hwdec':
          configuration.hwdec ??
          (configuration.enableHardwareAcceleration ? 'auto-safe' : 'no'),
      'vid': 'auto',
      'opengl-es': 'yes',
      'sub-use-margins': 'no',
      'sub-font-provider': 'none',
      'sub-scale-with-window': 'yes',
      'hwdec-codecs': 'h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1',
    };
    for (final entry in values.entries) {
      final name = entry.key.toNativeUtf8();
      final value = entry.value.toNativeUtf8();
      NativePlayer.mpv.mpv_set_property_string(player.ctx, name, value);
      calloc.free(name);
      calloc.free(value);
    }

    // Register a Flutter texture & start the native render thread. The native
    // side attaches an mpv_render_context onto [handle].
    final data = await _channel.invokeMethod('VideoOutputManager.Create', {
      'handle': handle.toString(),
    });
    debugPrint(data.toString());

    final int? id = data['id'];
    controller.id.value = id;

    // Return the [PlatformVideoController].
    return controller;
  }

  /// Sets the required size of the video output.
  @override
  Future<void>? setSize({int? width, int? height}) async {
    if (width == null || height == null) {
      return;
    }
    await _channel.invokeMethod('VideoOutputManager.SetSurfaceTextureSize', {
      'handle': player.handle.toString(),
      'width': width.toString(),
      'height': height.toString(),
    });
  }

  /// Disposes the instance. Releases allocated resources back to the system.
  Future<void> _dispose() async {
    // Dispose the [StreamSubscription]s.
    await _subscription?.cancel();
    // Release the native resources.
    final handle = player.handle;
    _controllers.remove(handle);
    await _channel.invokeMethod('VideoOutputManager.Dispose', {
      'handle': handle.toString(),
    });
  }

  /// [Lock] used to synchronize the [videoParams] subscription.
  final _lock = Lock();

  /// [StreamSubscription] for listening to video [Rect].
  StreamSubscription<VideoParams>? _subscription;

  /// Currently created [OhosVideoController]s.
  static final _controllers = HashMap<int, OhosVideoController>();

  /// [MethodChannel] for invoking platform specific native implementation.
  static const _channel = MethodChannel('com.alexmercerind/media_kit_video');
}
