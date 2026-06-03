import 'dart:io' show Platform;

abstract final class PlatformUtils {
  static final bool isMobile =
      Platform.isAndroid || Platform.isIOS || Platform.isOhos;

  @pragma("vm:platform-const")
  static final bool isDesktop =
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;
}
