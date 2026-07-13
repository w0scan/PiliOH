---
name: build_ohos
description: OHOS HAP 构建命令和流程
type: reference
---

# OHOS HAP 构建方式

**构建命令**：
```bash
source /Volumes/solid/flutter/startOhosFlutter
flutter build hap --debug --enable-experiment=private-named-parameters --pub
```

**HAP 输出路径**：`ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`

**安装到设备**：`hdc install <hap_path>`

**注意**：
- 必须先 source startOhosFlutter 切换到 OHOS 版 Flutter SDK
- 本地 stable Flutter SDK 不支持 `flutter build hap`
- Release 构建加 `--release` 和 `--dart-define-from-file=pili_release.json`