/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
// ignore_for_file: non_constant_identifier_names, camel_case_types
import 'dart:io';
import 'dart:ffi';

/// {@template android_helper}
///
/// AndroidHelper
/// -------------
///
/// Learn more: https://github.com/media-kit/media-kit-android-helper
///
/// {@endtemplate}
abstract class AndroidHelper {
  static set_java_vmDart _getSetJvm(String lib, String func) =>
      DynamicLibrary.open(
        lib,
      ).lookupFunction<set_java_vmCXX, set_java_vmDart>(func, isLeaf: true);

  // TODO: init in JNI_OnLoad
  /// {@macro android_helper}
  static void ensureInitialized({String? libmpv}) {
    set_java_vmDart? set_java_vm;
    MediaKitAndroidHelperGetJavaVMDart? MediaKitAndroidHelperGetJavaVM;
    // Look for the required symbols.
    try {
      set_java_vm = _getSetJvm(libmpv ?? 'libmpv.so', 'mpv_lavc_set_java_vm');
    } catch (_) {}
    if (set_java_vm == null) {
      try {
        set_java_vm = _getSetJvm('libavcodec.so', 'av_jni_set_java_vm');
      } catch (_) {}
    }

    if (set_java_vm == null) {
      throw UnsupportedError(
        'Cannot load mpv_lavc_set_java_vm (libmpv.so) or av_jni_set_java_vm (libavcodec.so).',
      );
    }

    try {
      MediaKitAndroidHelperGetJavaVM =
          DynamicLibrary.open('libmediakitandroidhelper.so').lookupFunction<
            MediaKitAndroidHelperGetJavaVMCXX,
            MediaKitAndroidHelperGetJavaVMDart
          >('MediaKitAndroidHelperGetJavaVM', isLeaf: true);
    } catch (_) {}

    if (MediaKitAndroidHelperGetJavaVM == null) {
      throw UnsupportedError(
        'Cannot load MediaKitAndroidHelperGetJavaVM (libmediakitandroidhelper.so).',
      );
    }

    Pointer<Void> vm = nullptr;
    while (true) {
      // Invoke av_jni_set_java_vm to set reference to JavaVM*.
      // It is important to call av_jni_set_java_vm so that libavcodec can access JNI environment & thus, mediacodec APIs.
      vm = MediaKitAndroidHelperGetJavaVM();
      if (vm != nullptr) {
        set_java_vm(vm);
        break;
      }
      sleep(const Duration(milliseconds: 20));
    }
  }
}

typedef set_java_vmCXX = Int32 Function(Pointer<Void> vm);
typedef set_java_vmDart = int Function(Pointer<Void> vm);

typedef MediaKitAndroidHelperGetJavaVMCXX = Pointer<Void> Function();
typedef MediaKitAndroidHelperGetJavaVMDart = Pointer<Void> Function();
