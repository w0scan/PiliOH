import 'dart:convert' show base64;

import 'package:flutter/services.dart';

/// OpenHarmony native file picker bridge.
///
/// On OHOS the `file_picker` package has no platform implementation, so this
/// lightweight MethodChannel drives `@ohos.file.picker` (DocumentViewPicker)
/// for save/open dialogs. On other platforms, fall back to file_picker.
abstract final class OhosFilePicker {
  static const MethodChannel _channel = MethodChannel('piliplus/file_picker');

  /// Save [bytes] to a user-chosen location. Returns true on success.
  static Future<bool> saveFile({
    required String fileName,
    required List<int> bytes,
  }) async {
    try {
      final base64Str = base64.encode(bytes);
      final ok = await _channel.invokeMethod<bool>('saveFile', {
        'fileName': fileName,
        'base64': base64Str,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Open system file picker, read file content, return as bytes. Returns null
  /// if the user cancels or an error occurs.
  static Future<List<int>?> pickFile() async {
    try {
      final base64Str = await _channel.invokeMethod<String>('pickFile');
      if (base64Str == null || base64Str.isEmpty) return null;
      return base64.decode(base64Str);
    } catch (_) {
      return null;
    }
  }

  /// Read plain text from the system pasteboard. The OHOS Flutter embedder's
  /// clipboard path is gated behind READ_PASTEBOARD (a system_basic permission
  /// a normal app can't be granted), so read natively instead. Returns null on
  /// failure or empty clipboard.
  static Future<String?> readClipboard() async {
    try {
      final text = await _channel.invokeMethod<String>('readClipboard');
      if (text == null || text.isEmpty) return null;
      return text;
    } catch (_) {
      return null;
    }
  }
}
