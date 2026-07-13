import 'dart:typed_data';

import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:dio/dio.dart';

class RemoteCacheClient {
  RemoteCacheClient._();

  static RemoteCacheClient? fromSettings() {
    final url = Pref.remoteCacheUrl.trim();
    final token = Pref.remoteCacheToken.trim();
    if (url.isEmpty || token.isEmpty) return null;
    return RemoteCacheClient._configured(url, token);
  }

  factory RemoteCacheClient._configured(String url, String token) {
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    return RemoteCacheClient._()
      .._dio = Dio(
        BaseOptions(
          baseUrl: '$baseUrl/api/v1',
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Authorization': 'Bearer $token'},
        ),
      )
      ..baseUrl = baseUrl;
  }

  late Dio _dio;
  late String baseUrl;
  Map<String, String> get mediaHeaders => {
    'Authorization': 'Bearer ${Pref.remoteCacheToken}',
  };

  Future<bool> health() async =>
      (await _dio.get<Map<String, dynamic>>('/health')).data?['ok'] == true;

  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async =>
      (await _dio.post<Map<String, dynamic>>('/cache', data: body)).data!;

  Future<String> createTask(Map<String, dynamic> body) async {
    final data = await create(body);
    final taskKey = data['taskKey'] ?? data['key'];
    if (taskKey is String && taskKey.isNotEmpty) return taskKey;
    throw StateError('远程服务器未返回 taskKey');
  }

  Future<void> upload(String taskKey, String type, Uint8List bytes) =>
      _dio.put<void>(
        '/cache/$taskKey/$type',
        data: Stream.value(bytes),
        options: Options(
          contentType: 'application/octet-stream',
          headers: {'content-length': bytes.length},
        ),
      );

  Future<List<dynamic>> library() async =>
      (await _dio.get<List<dynamic>>('/library')).data ?? const [];

  Future<List<dynamic>> tasks() async =>
      (await _dio.get<List<dynamic>>('/tasks')).data ?? const [];

  Future<void> taskAction(String taskKey, String action) =>
      _dio.post<void>('/tasks/$taskKey/$action');

  Future<void> delete(String taskKey) => _dio.delete<void>('/cache/$taskKey');

  Future<void> updateMetadata(
    String taskKey,
    Map<String, dynamic> entryJson,
    Map<String, dynamic> indexJson,
  ) => _dio.put<void>(
    '/cache/$taskKey/metadata',
    data: {'entryJson': entryJson, 'indexJson': indexJson},
  );

  String fileUrl(String taskKey, String name) =>
      '$baseUrl/api/v1/cache/$taskKey/files/$name';

  Future<Uint8List> fileBytes(String taskKey, String name) async =>
      (await _dio.get<List<int>>(
        '/cache/$taskKey/files/$name',
        options: Options(responseType: ResponseType.bytes),
      )).data!.toUint8List();
}

extension on List<int> {
  Uint8List toUint8List() => Uint8List.fromList(this);
}
