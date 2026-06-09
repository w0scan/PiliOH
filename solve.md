# HarmonyOS 适配问题与解决方案

## 一、Dart 版本兼容性

### 问题1：`private-named-parameters` 实验特性不支持

**现象**：编译报错 908 处 `private-named-parameters` 错误。

**原因**：项目源码使用 Dart 3.12 的 `this._privateField` 语法（构造函数中私有字段自动脱 underscore 作为命名参数），但 HarmonyOS Flutter SDK 使用的 Dart 3.11.1 不支持该特性。

**解决**：构建命令添加 `--enable-experiment=private-named-parameters`：
```bash
flutter build hap --debug --enable-experiment=private-named-parameters
```

### 问题2：`RenderReserveBtn` 构造函数参数不匹配

**文件**：`lib/pages/member/widget/reserve_button.dart`

**原因**：Dart 3.11.1 中 `required this._color` 不会自动创建公开命名参数 `color`，导致调用方传参名不匹配。

**解决**：改为显式参数 + 初始化列表：
```dart
// 修改前
RenderReserveBtn({required int count, required this._color})
// 修改后
RenderReserveBtn({required int count, required Color color})
    : _count = count, _color = color
```

## 二、插件方法通道挂起（白屏根本原因）

### 核心问题

HarmonyOS 平台只有 2 个插件有原生实现（`saver_gallery`、`flutter_volume_controller`），其余插件均无 ohos 原生代码。当 Dart 调用这些插件的方法通道时，Future 永远不会完成，导致 `main()` 被永久阻塞，无法到达 `runApp()`，表现为白屏。

### 修复清单

| 阻塞点 | 插件 | 文件 | 修复方式 |
|--------|------|------|----------|
| `MediaKit.ensureInitialized()` | media_kit | lib/main.dart | `if (!Platform.isOhos)` 跳过 |
| `getApplicationSupportDirectory()` | path_provider | lib/main.dart | 硬编码路径 `/data/storage/el2/base/haps/entry/files` |
| `getTemporaryDirectory()` | path_provider | lib/main.dart | 硬编码路径 `/data/storage/el2/base/haps/entry/cache` |
| `CacheManager.ensureInitialized()` | path_provider | lib/main.dart | `if (!Platform.isOhos)` 跳过 |
| `setupServiceLocator()` → `initAudioService()` | audio_service | lib/main.dart | `if (!Platform.isOhos)` 跳过 |
| `LoginUtils.setWebCookie()` | flutter_inappwebview | lib/http/init.dart | `if (!Platform.isOhos)` 跳过 |
| `getApplicationDocumentsDirectory()` | path_provider | lib/services/logger.dart | 使用已有 `appSupportDirPath` |
| `NativePlayer.apiVersion` | media_kit (FFI) | lib/main.dart | 返回 `'N/A (ohos)'` 字符串 |
| `Catcher2` 构造函数 | device_info_plus 等 | lib/main.dart | ohos 上直接用 `runApp()` |

### 硬编码的 ohos 路径

```dart
// 应用数据目录
appSupportDirPath = '/data/storage/el2/base/haps/entry/files';
// 临时缓存目录
tmpDirPath = '/data/storage/el2/base/haps/entry/cache';
```

这些路径上的 `dart:io` 文件操作（Hive、Dio 缓存等）均可正常工作。

## 三、图片加载问题

### 问题：首页视频卡片图片不显示

**原因**：图片加载使用 `cached_network_image_ce` 库，其内部 `DefaultCacheManager.init()` 默认调用 `path_provider` 的 `getTemporaryDirectory()` 获取缓存目录。在 ohos 上该方法通道无原生实现，Future 永久挂起。同时 `DefaultCacheManager.instance` 为 null，`CachedNetworkImageProvider` 访问 `instance!` 时失败，导致图片降至 errorWidget（占位符）。

**解决方案**：在 ohos 上初始化 `DefaultCacheManager` 时传入自定义的 `cacheDirectoryProvider`，使用硬编码的 `tmpDirPath` 替代 `getTemporaryDirectory()`。

**文件**：`lib/utils/cache_manager.dart`
```dart
static Future<void> ensureInitialized() async {
    final cacheDir = Platform.isOhos
        ? () async => Directory(tmpDirPath)
        : null;
    final instance = cacheDir != null
        ? await DefaultCacheManager.init(cacheDirectoryProvider: cacheDir)
        : await DefaultCacheManager.init();
    manager = instance;
}
```

同时在 `main.dart` 的 `Future.wait` 之后为 ohos 单独调用 `CacheManager.ensureInitialized()`，确保 `tmpDirPath` 已赋值。

## 四、当前状态

- ✅ 应用正常启动，到达 `runApp()`
- ✅ 界面正常显示（与 Android 平台一致）
- ✅ HTTP API 请求正常（B站 API 认证、首页 Feed 数据）
- ✅ 资源文件、字体等加载正常
- ✅ 图片加载正常（视频卡片缩略图、头像等）

---

# 鸿蒙原生双 AVPlayer 播放器（在线/离线，音视频分轨同步）

目标：新增一个可在「音视频设置」开关的鸿蒙原生播放方案，用两个
`@ohos.multimedia.media` AVPlayer 分别播放 B站 DASH 的视频轨与音频轨并保持同步，
作为 media_kit(mpv) 之外的可选后端。参考了纯 ArkTS 项目
`/Users/ws/DevEcoStudioProjects/PiliPlus` 的 `AvSyncPlayerController.ets`。

最终架构：视频轨=静音主时钟，渲染进**原生 XComponent**；音频轨=出声，无 surface。
XComponent 经 **PlatformView(surface 合成)** 嵌入 Flutter 树；漂移同步在视频轨的
`timeUpdate` 里比较音频轨 `currentTime`，超阈值则 seek 一路对齐另一路。

下面按「踩坑顺序」记录，重点是**误区**——很多时间花在错误方向上。

## 一、取流与请求头

### 问题：在线视频 prepare 报 5400106（unsupported format），黑屏
**现象**：两个 AVPlayer 都走到 `initialized` → `error`，code 5400106，偶发 5411006。
一开始以为是 B站 `.m4s` 容器不被识别，或编码(HEVC/AV1)不支持——**这是误区**。

**真因**：请求头是空的。加诊断日志打印 `headers` 发现是 `{}`。B站 upos CDN 防盗链
按 UA+Referer 校验，没头就被拒，AVPlayer 把拒绝响应当成"无法识别的格式"→ 5400106。

**根因**：`flutter_ohos` 的 StandardMessageCodec 把 Dart `Map` 解码成 **ES6 `Map`
对象**（不是普通 object）。原生侧 `call.argument('headers') as Record<string,string>`
拿到的是 Map，`JSON.stringify` 出来是 `{}`，传给 `createMediaSourceWithUrl` 等于没头。

**解决**：写 `toRecord()` 把 ES6 Map 转成普通 Record：
```ts
if (value instanceof Map) {
  (value as Map<ESObject,ESObject>).forEach((v,k)=>{ out[String(k)]=String(v); });
}
```
头用与 media_kit 一致的 `User-Agent: <Web UA>`、`Referer: https://www.bilibili.com`。
**注意必须是 Web UA**（不是 App UA），upos CDN 按浏览器 UA 校验。

### 取流方式
- 在线：`media.createMediaSourceWithUrl(url, headers)` → `setMediaSource(src)`（无 strategy）。
- 离线：`player.fdSrc = { fd, offset:0, length }`，fd 由 `fileIo.openSync` 取，
  release 时逐个 `closeSync`，否则 fd 泄漏。

## 二、AVPlayer 状态机

### 问题：setSpeed 报 5400102（operation not allowed）
**真因**：Dart 侧 `_initializePlayer` 在播放器还只是 `initialized`（未 prepared）时就调
了 `setSpeed`。AVPlayer 的 `setSpeed` 只能在 prepared 之后调用。
**解决**：把 `applySpeed()` 延后到两轨都 `prepared`（`maybeStart` 里）才执行；
倍速=1.0 时直接跳过。

### 起播时序
两个 player 各自 `initialized→prepared` 是异步的，必须**两轨都 prepared 后**才一起
`play()`（`maybeStart` 用 `videoReady && audioReady` 闸门），否则音视频起步就不齐。

## 三、视频画面进 Flutter —— 最大的坑

这块走了**两条死路**才找到正解，记下来避免重蹈。

### 误区/死路 1：Flutter 纹理（OH_NativeImage）
最初想用 `TextureRegistry.registerTexture` 拿 `SurfaceTextureEntry.getSurfaceId()`
当 AVPlayer 的 surface，Flutter 端 `Texture(textureId)` 显示。
**结果**：音频/同步都正常，但视频**黑屏**。日志报
`ohos_egl_surface.cpp: Could not make the context current — EGL_BAD_ACCESS`。
**原因**：AVPlayer 的视频输出和 Flutter 自己的 EGL 上下文冲突，AVPlayer 没法往
Flutter 纹理的 OH_NativeImage surface 合成。**纹理路不通。**

期间还浪费时间在错误假设上：以为是纹理 buffer size=0（在 `videoSizeChange`/`prepared`
里 `setTextureBufferSize`），以为是 `SizedBox(0,0)` 导致 FittedBox NaN 崩溃——
都不是根因，纹理方案本身就走不通。

### 误区/死路 2：PlatformView 默认（texture 合成）
改用 `OhosView` widget。但 `OhosView` 内部走 `initOhosView` = **texture 合成模式**，
仍然是上面那个 EGL 冲突，依旧黑屏，且渲染期异常把整个播放器页打崩。

### 正解：PlatformView + XComponent + **surface 合成**
- 原生侧写 `NativePlayerView extends PlatformView`，`getView()` 返回一个
  `@Builder`，里面放真正的 `XComponent({type: SURFACE})`；`onLoad` 里
  `getXComponentSurfaceId()` 拿到 surfaceId 交给 AVPlayer（和参考纯 ArkTS 项目一样）。
- 在 `onAttachedToEngine` 里 `binding.getPlatformViewRegistry().registerViewFactory(...)`。
- Dart 侧**不要用 `OhosView`**，要用 `PlatformViewLink` + `PlatformViewsService.
  initSurfaceOhosView` + `OhosViewSurface`（surface 合成，在原生视图层合成，绕开 EGL 冲突）。

注意点：
- `Params` 没从 `@ohos/flutter_ohos` 顶层导出，要深路径 import：
  `@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView`。
- `PlatformViewHitTestBehavior` 不是 const 上下文可用——别加 `const`。

### 问题：onLoad/factory.create 从不触发（黑屏、无控件、无弹幕、无声音）
这是**最隐蔽、耗时最久**的一个。注册成功（日志确认 `reg=PlatformViewRegistryImpl
ok=true`），但平台视图创建链一个都不走。

**误区**：以为是 PlatformView 注册到了空 registry（EmptyPlatformViewRegistry）——
排查后排除了。也怀疑过 surface 合成模式没实例化 XComponent。

**真因**：`pages/video/view.dart` 里构建播放器组件的门控：
```dart
plPlayerController?.videoController == null ? SizedBox.shrink() : PLVideoPlayer(...)
```
`videoController` 是 **media_kit** 的，原生模式下永远是 null → 整个 `PLVideoPlayer`
（视频+控件+弹幕全在里面）被跳过，啥都不渲染。
**解决**：门控放开为 `videoController == null && !isNativePlayer`。
**教训**：黑屏+控件+弹幕全没 → 优先怀疑「整个播放器组件没被构建」，而不是渲染层。
应该一开始就在 view 的 Obx 分支加日志确认有没有执行，能省好几轮。

## 四、进度条 / 弹幕 / 状态全部收不到

### 问题：进度不动、弹幕不出、播放器组件反复重建
**真因**：从纹理方案切到 PlatformView 时，删掉了 `OhosNativePlayer.create()`。
而 `create()` 里调用的 `_ensureHandler()` 才是注册 Dart 侧
`channel.setMethodCallHandler` 的地方。删掉后，**所有 native→Dart 回调
（onPosition/onPlayingChanged/onDuration/onCompleted…）被静默丢弃**。
原生侧自己播得好好的，但 Dart 完全收不到事件 → 进度/状态/弹幕全死，
还因为状态不同步导致页面反复重建。
**解决**：在 `setSource` 里也调 `_ensureHandler()`（PlatformView 模式没有 create() 了）。
**教训**：MethodChannel 改造时，**回调 handler 的注册点**容易随重构丢失，
而且丢了不报错，只是静默无响应——要专门确认 setMethodCallHandler 仍被调用。

### 弹幕的位置粒度
弹幕按 100ms 桶取数据（`videoPositionListen`），但 AVPlayer 的 `timeUpdate` 只有约
1Hz，几乎每次都落在空桶 → 弹幕基本不出。
**解决**：在 controller 里用 `Stopwatch` + 100ms `Timer.periodic` 做**位置插值**，
以 `timeUpdate` 为权威基准、中间插值推进，seek/暂停时重置基准。进度条也因此变平滑。

## 五、画面比例（竖屏被拉伸）

### 误区：只设 AVPlayer 的 videoScaleType
设 `videoScaleType = VIDEO_SCALE_TYPE_FIT` 不够——XComponent 自身被放在一个横向铺满
的盒子里，竖屏视频仍被拉伸。
**解决**：Dart 侧用 `Center(AspectRatio(aspectRatio: w/h, child: PlatformView))`，
按视频实际宽高定框（w/h 来自 `setDataSource` 的 width/height），让盒子本身是竖的。
（videoScaleType=FIT 也保留，双保险。）

## 六、与 media_kit 共存

- `PlPlayerController` 复用同一套 observable（position/duration/buffered/playerStatus）
  和 listener 列表驱动现有 UI，原生后端只是另一个数据来源。
- 所有 media_kit 强解包（`videoPlayerController!`、`videoController!`、`.state.*`）在
  原生模式下都要 null-guard 或分支；`play_pause_btn` 改成读 `playerStatus`（后端无关）。
- PiP/超分/mpv 截图等 media_kit 专有能力在原生模式下按约定降级（隐藏/早退）。
- 开关 `useNativePlayer` 默认关、需重启生效；仅 `Platform.isOhos && 非直播` 生效
  （直播是单条流，不需要双 player）。

## 七、调试经验（鸿蒙 release 包）

- **release 包 strip 掉 Dart 堆栈**，`Log.i` 也被过滤——诊断日志要用 `Log.e` / 
  `debugPrint`（经 hilog 输出）才看得到；查问题时先把日志级别降到能看见。
- 反复出现的 `Another exception: DiagnosticsProperty<void>` 常常是同一个错误被报两次，
  且可能是**无害的预存问题**（如 `native_device_orientation` 在 OHOS 无实现的
  MissingPluginException），别被它带偏，要找**第一个**真正的异常。
- 定位「黑屏」类问题的正确顺序：① 确认走的是哪条播放路径（加日志）→ ② 确认播放器
  **组件有没有被构建**（view 分支加日志）→ ③ 才看渲染/surface 层。本次在 ③ 上耗了
  太久，根因其实在 ②。
