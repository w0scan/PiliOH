import 'package:flutter/services.dart';

abstract final class OhosDownloadDirectory {
  static const MethodChannel _channel = MethodChannel(
    'piliplus/download_directory',
  );

  static Future<String?> getPath() => _getPath('getDownloadDirectory');

  static Future<String?> authorize() => _getPath(
    'authorizeDownloadDirectory',
  );

  static Future<String?> _getPath(String method) async {
    try {
      final path = await _channel.invokeMethod<String>(method);
      return path == null || path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }
}
