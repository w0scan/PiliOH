import { PlatformView, PlatformViewFactory } from '@ohos/flutter_ohos';
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import type common from '@ohos.app.ability.common';
import NativeDualPlayer from './NativeDualPlayer';

// ArkUI content for the platform view: a SURFACE XComponent whose surface the
// dual AVPlayer renders into. On load we hand its surfaceId to NativeDualPlayer
// (matching the reference app's XComponent + getXComponentSurfaceId approach);
// rendering into a real XComponent surface avoids the EGL conflict seen when
// feeding AVPlayer into a Flutter texture's OH_NativeImage.
@Builder
function buildNativePlayerView(params: Params): void {
  NativePlayerXComponent({
    view: params.platformView as NativePlayerView,
  })
}

@Component
struct NativePlayerXComponent {
  view!: NativePlayerView;

  build() {
    XComponent({
      type: XComponentType.SURFACE,
      controller: this.view.xController,
    })
      .onLoad(() => {
        this.view.onSurfaceReady(this.view.xController.getXComponentSurfaceId());
      })
      .onDestroy(() => {
        this.view.onSurfaceDestroyed();
      })
      .width('100%')
      .height('100%')
  }
}

export class NativePlayerView extends PlatformView {
  xController: XComponentController = new XComponentController();
  private player: NativeDualPlayer;

  constructor(player: NativeDualPlayer) {
    super();
    this.player = player;
  }

  getView(): WrappedBuilder<[Params]> {
    return wrapBuilder(buildNativePlayerView);
  }

  onSurfaceReady(surfaceId: string): void {
    this.player.onViewSurfaceReady(surfaceId);
  }

  onSurfaceDestroyed(): void {
    this.player.onViewSurfaceDestroyed();
  }

  dispose(): void {
    this.onSurfaceDestroyed();
  }
}

export class NativePlayerViewFactory extends PlatformViewFactory {
  private player: NativeDualPlayer;

  constructor(player: NativeDualPlayer) {
    // No creation args from Dart.
    super(null);
    this.player = player;
  }

  create(context: common.Context, viewId: number, args: Object): PlatformView {
    return new NativePlayerView(this.player);
  }
}
