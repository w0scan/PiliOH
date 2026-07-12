# 上游同步限制清单

同步上游代码时，以下播放器相关文件包含OHOS专属适配逻辑，**不应被上游覆盖**，需手动合并或跳过：

## 核心播放器代码（OHOS原生播放器适配）

### `lib/plugin/pl_player/controller.dart`
- `isNativePlayer` getter — OHOS原生播放器判断逻辑
- `isBuffering` 初始值 — `false.obs`（上游为`true.obs`，会导致加载指示器一直显示）
- `_createNativePlayer()` — OHOS双AVPlayer初始化
- `_setupNativeCallbacks()` — 原生播放器回调绑定（onPosition/onDuration/onBuffered/onBuffering/onPlayingChanged/onCompleted/onError/onVideoSize）
- **AVSession通知栏**：`onBuffering`/`onPlayingChanged`/`onCompleted`回调中的`OhosNativePlayer.updatePlaybackState`调用
- `play()`/`pause()`/`seek()`/`setSpeed()` 中的原生播放器分支
- `onError` 回调中的状态重置（`isBuffering=false`, `dataStatus=error`, `playerStatus=paused`）
- `onPlayingChanged(true)` 中的 `isBuffering.value = false`
- `switchDataSource()` 中的原生播放器分支
- `release()` 中的 `OhosNativePlayer` 清理
- `nativeVideoSize` / `nativeTextureId` 响应式变量

### `lib/services/audio_handler.dart`
- **AVSession通知栏**：`setMediaItem`中`OhosNativePlayer.setMediaMetadata`调用；`setPlaybackState`中`OhosNativePlayer.updatePlaybackState`调用；`clear`中OHOS元数据和状态清理
- `_videoWidget` getter 中的 `isNativePlayer` 分支 — **关键：使用`const NativePlayerPlatformView()`+非响应式`width`/`height`，不能用`Obx`监听`nativeVideoSize`重建平台视图（会销毁XComponent surface导致黑屏）**
- 全屏相关逻辑中的原生播放器适配

### `lib/plugin/pl_player/native/native_player_platform_view.dart`
- **整个文件** — OHOS PlatformView + XComponent SURFACE模式实现
- 必须使用`initSurfaceOhosView`（SURFACE模式），不能用`initOhosView`（Texture模式会导致EGL冲突黑屏）

### `ohos/entry/src/main/ets/plugins/NativeDualPlayer.ets`
- **整个文件** — OHOS双AVPlayer实现
- `videoScaleType = VIDEO_SCALE_TYPE_FIT` — 保持视频比例
- `setSource`/`tryStart`/`setupPlayers`/`bindVideoEvents`/`bindAudioEvents`/`maybeStart` 全部逻辑
- **AVSession通知栏**：`mediaTitle`/`mediaArtist`/`mediaCoverUri`/`mediaDurationMs`/`mediaIsLive`元数据属性；`updateAVMetadata()`/`updateAVPlaybackState()`/`updateAVPlaybackPosition()`方法；`ensureAVSession`中控制命令回调注册（play/pause/seek/rewind/fastForward）；`setMediaMetadata`/`updatePlaybackState` MethodChannel处理器；`timeUpdate`/`durationUpdate`回调中的AVSession同步

### `ohos/entry/src/main/ets/plugins/NativePlayerView.ets`
- **整个文件** — PlatformView + XComponent SURFACE渲染

### `ohos/entry/src/main/ets/plugins/PiPManager.ets`
- **整个文件** — OHOS画中画管理器
- 需同时支持mpv（rebind纹理）和AVPlayer（切换surfaceId）两种PiP模式
- `registerNativePlayer`/`unregisterNativePlayer` — 原生播放器注册/注销
- `isNativeMode` — 区分mpv和AVPlayer的PiP模式

### `lib/utils/ohos/ohos_pip_helper.dart`
- `enterPip`的`isNativePlayer`参数 — 原生播放器PiP标志
- `isInPip` ValueNotifier — PiP状态监听

### `lib/utils/ohos/ohos_native_player.dart`
- **整个文件** — OHOS原生播放器Dart桥接
- `setMediaMetadata`/`updatePlaybackState` — AVSession通知栏元数据和播放状态同步

### `lib/plugin/pl_player/controller.dart`
- `enterPip`中原生播放器分支 — 传递`isNativePlayer: true`
- `isPipMode` getter — 需包含`Platform.isOhos && OhosPipHelper.isInPip.value`
- `_setupNativeCallbacks`中的`OhosPipHelper.setPlaybackState`/`onPlayPause` — PiP控制面板同步

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
5. **全屏视频拉伸** — SURFACE模式下XComponent不受Flutter布局约束（AspectRatio无效），需配合`VIDEO_SCALE_TYPE_FIT`保持视频比例；surface重建后需重新设置`videoScaleType`；**注意：`setXComponentSurfaceRect`不可用**——`onAreaChange`返回vp单位而`setXComponentSurfaceRect`期望px单位，vp→px转换会导致视频只在左上角小区域显示，应完全依赖`VIDEO_SCALE_TYPE_FIT`自动letterbox
6. **原生播放器PiP** — `PiPManager`需同时支持mpv（rebind纹理）和AVPlayer（切换surfaceId）两种模式；`NativeDualPlayer`需提供`enterPip`/`exitPip`方法切换视频渲染surface；`isPipMode`需包含OHOS检查；原生播放器后台暂停需单独处理
7. **后台播放中断** — OHOS应用切后台被系统暂停；需三要素：①`module.json5`声明`backgroundModes:["audioPlayback"]`+`ohos.permission.KEEP_BACKGROUND_RUNNING`权限 ②AVSession注册（不注册会被系统暂停音频）③`backgroundTaskManager.startBackgroundRunning`长时任务申请；`NativeDualPlayer`在playing状态启动AVSession+长时任务，paused/completed/release时停止；`EntryAbility`需设置`NativeDualPlayer.abilityContext`
8. **通知栏播放控件** — AVSession需设置AVMetadata（title/artist/mediaImage/duration/isLive）+AVPlaybackState（state/position/speed/bufferedTime/duration）+控制命令回调（play/pause/seek/rewind/fastForward）；Dart端通过`OhosNativePlayer.setMediaMetadata`/`updatePlaybackState`传递媒体元数据和播放状态；`audio_handler.dart`中`setMediaItem`/`setPlaybackState`/`clear`添加OHOS平台分支；`pl_player/controller.dart`中OHOS原生播放器回调（onBuffering/onPlayingChanged/onCompleted）添加AVSession状态同步