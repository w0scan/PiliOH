# 上游同步限制清单

同步上游代码时，以下播放器相关文件包含OHOS专属适配逻辑，**不应被上游覆盖**，需手动合并或跳过：

## 核心播放器代码（OHOS原生播放器适配）

### `lib/plugin/pl_player/controller.dart`
- `isNativePlayer` getter — OHOS原生播放器判断逻辑
- `isBuffering` 初始值 — `false.obs`（上游为`true.obs`，会导致加载指示器一直显示）
- `_createNativePlayer()` — OHOS双AVPlayer初始化
- `_setupNativeCallbacks()` — 原生播放器回调绑定（onPosition/onDuration/onBuffered/onBuffering/onPlayingChanged/onCompleted/onError/onVideoSize）
- `play()`/`pause()`/`seek()`/`setSpeed()` 中的原生播放器分支
- `onError` 回调中的状态重置（`isBuffering=false`, `dataStatus=error`, `playerStatus=paused`）
- `onPlayingChanged(true)` 中的 `isBuffering.value = false`
- `switchDataSource()` 中的原生播放器分支
- `release()` 中的 `OhosNativePlayer` 清理
- `nativeVideoSize` / `nativeTextureId` 响应式变量

### `lib/plugin/pl_player/view/view.dart`
- `_videoWidget` getter 中的 `isNativePlayer` 分支 — **关键：使用`const NativePlayerPlatformView()`+非响应式`width`/`height`，不能用`Obx`监听`nativeVideoSize`重建平台视图（会销毁XComponent surface导致黑屏）**
- 全屏相关逻辑中的原生播放器适配

### `lib/plugin/pl_player/native/native_player_platform_view.dart`
- **整个文件** — OHOS PlatformView + XComponent SURFACE模式实现
- 必须使用`initSurfaceOhosView`（SURFACE模式），不能用`initOhosView`（Texture模式会导致EGL冲突黑屏）

### `ohos/entry/src/main/ets/plugins/NativeDualPlayer.ets`
- **整个文件** — OHOS双AVPlayer实现
- `videoScaleType = VIDEO_SCALE_TYPE_FIT` — 保持视频比例
- `setSource`/`tryStart`/`setupPlayers`/`bindVideoEvents`/`bindAudioEvents`/`maybeStart` 全部逻辑

### `ohos/entry/src/main/ets/plugins/NativePlayerView.ets`
- **整个文件** — PlatformView + XComponent SURFACE渲染

## 上游API变更适配注意

上游可能重构以下API，同步时需注意OHOS适配代码的对应修改：

| 上游变更 | OHOS适配点 |
|---------|-----------|
| `position` 从 `Duration` 变为 `RxInt(0)` | `_nativePositionMs` 相关逻辑 |
| `BlockMixin` 移除 `onBlockPosition`/`startBlockListener` | OHOS mixin 中保留这些方法 |
| `defaultDecode`+`secondDecode` 合并为 `preferCodecs` | OHOS 解码格式设置 |
| `screenshot()` 返回类型从 `ui.Image` 变为 `Uint8List` | 截图功能适配 |
| `showVideoBottomSheet` 新增 `isFullScreen` 参数 | 底部弹窗适配 |
| `NativePlayerPlatformView` 构造函数参数变更 | 平台视图创建逻辑 |

## 历史问题记录

1. **黑屏（videoController null检查）** — `plPlayer()`中`videoController==null`检查在原生路径始终为true，需添加`isNativePlayer`豁免
2. **加载指示器一直显示** — `isBuffering`初始值`true.obs`+`playerStatus`初始值`playing`→改为`false.obs`
3. **控件不显示** — `_videoWidget`中`Obx`监听`nativeVideoSize.value`导致平台视图销毁重建→使用`const NativePlayerPlatformView()`+非响应式尺寸
4. **视频黑屏（AV1不支持）** — 设备不支持AV1硬解(错误码5400106)，`fnval`参数需注意
5. **全屏视频拉伸** — SURFACE模式下XComponent不受Flutter布局约束（AspectRatio无效），需配合`VIDEO_SCALE_TYPE_FIT`+`setXComponentSurfaceRect`手动计算letterbox渲染区域保持比例；surface重建后需重新设置`videoScaleType`