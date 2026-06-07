import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart' show OneSequenceGestureRecognizer;
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart'
    show
        PlatformViewsService,
        OhosViewController,
        TextDirection;
import 'package:flutter/widgets.dart';

/// Embeds the native dual-AVPlayer's XComponent using SURFACE composition
/// (initSurfaceOhosView) rather than texture composition. Surface composition
/// composes the platform view in the native view hierarchy, avoiding the
/// Flutter-texture EGL context conflict that produced a black frame.
class NativePlayerPlatformView extends StatelessWidget {
  const NativePlayerPlatformView({super.key});

  static const String _viewType = 'piliplus/native_player_view';

  @override
  Widget build(BuildContext context) {
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (context, controller) {
        return OhosViewSurface(
          controller: controller as OhosViewController,
          gestureRecognizers:
              const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.transparent,
        );
      },
      onCreatePlatformView: (params) {
        final controller = PlatformViewsService.initSurfaceOhosView(
          id: params.id,
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
        );
        controller.addOnPlatformViewCreatedListener(
          params.onPlatformViewCreated,
        );
        controller.create();
        return controller;
      },
    );
  }
}
