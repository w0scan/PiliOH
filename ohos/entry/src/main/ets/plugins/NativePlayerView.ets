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
      .onAreaChange((oldArea: Area, newArea: Area) => {
        // When the layout changes (e.g. fullscreen toggle), recalculate the
        // letterbox surface rect to preserve video aspect ratio.
        const w = Number(newArea.width);
        const h = Number(newArea.height);
        if (w > 0 && h > 0) {
          this.view.onLayoutChanged(w, h);
        }
      })
      .width('100%')
      .height('100%')
  }
}

export class NativePlayerView extends PlatformView {
  xController: XComponentController = new XComponentController();
  private player: NativeDualPlayer;
  // Cached container dimensions from onAreaChange, used by NativeDualPlayer
  // to recalculate surface rect when video size becomes available.
  containerWidth: number = 0;
  containerHeight: number = 0;

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

  onLayoutChanged(width: number, height: number): void {
    this.containerWidth = width;
    this.containerHeight = height;
    this.player.updateSurfaceRect(width, height);
  }

  dispose(): void {
    this.onSurfaceDestroyed();
  }
}

export class NativePlayerViewFactory extends PlatformViewFactory {
  private player: NativeDualPlayer;
  // The most recently created NativePlayerView, so NativeDualPlayer can
  // reach the XComponentController to call setXComponentSurfaceRect.
  currentView: NativePlayerView | null = null;

  constructor(player: NativeDualPlayer) {
    // No creation args from Dart.
    super(null);
    this.player = player;
  }

  create(context: common.Context, viewId: number, args: Object): PlatformView {
    const view = new NativePlayerView(this.player);
    this.currentView = view;
    return view;
  }
}
