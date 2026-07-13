import 'package:flutter/services.dart';

abstract final class OhosDownloadDirectory {
  static const MethodChannel _channel = MethodChannel(
    'piliplus/download_directory',
  );

  static Future<String?> getPath() async {
    try {
      final path = await _channel.invokeMethod<String>('getDownloadDirectory');
      return path == null || path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }
}
