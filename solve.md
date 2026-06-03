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
