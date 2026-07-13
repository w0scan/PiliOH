import 'package:PiliPlus/models_new/download/bili_download_entry_info.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/services/download/remote_cache_client.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class RemoteCacheEntry {
  RemoteCacheEntry({required this.taskKey, required this.entry, this.task});
  final String taskKey;
  final BiliDownloadEntryInfo entry;
  final Map<String, dynamic>? task;
}

class RemoteCacheService extends GetxService {
  final entries = <RemoteCacheEntry>[].obs;
  final loading = false.obs;
  String? error;

  Set<int> get cidSet => entries.map((e) => e.entry.cid).toSet();
  bool hasCid(int cid) => entries.any((e) => e.entry.cid == cid);

  bool hasTaskKey(String taskKey) => entries.any((e) => e.taskKey == taskKey);

  Future<void> refresh() async {
    final client = RemoteCacheClient.fromSettings();
    if (client == null) {
      entries.clear();
      error = '请先配置远程缓存服务器';
      return;
    }
    loading.value = true;
    try {
      final data = await client.library();
      entries.value = data.map((raw) {
        final item = Map<String, dynamic>.from(raw as Map);
        return RemoteCacheEntry(
          taskKey: item['taskKey'] as String,
          entry: BiliDownloadEntryInfo.fromJson(
            Map<String, dynamic>.from(item['entryJson'] as Map),
          ),
          task: item['task'] == null
              ? null
              : Map<String, dynamic>.from(item['task'] as Map),
        );
      }).toList();
      error = null;
    } catch (e) {
      error = e.toString();
    } finally {
      loading.value = false;
    }
  }

  Future<void> action(RemoteCacheEntry entry, String action) async {
    await RemoteCacheClient.fromSettings()!.taskAction(entry.taskKey, action);
    await refresh();
  }

  Future<void> delete(RemoteCacheEntry entry) async {
    await RemoteCacheClient.fromSettings()!.delete(entry.taskKey);
    await refresh();
  }

  Future<void> updateDanmakuAndMetadata(RemoteCacheEntry entry) async {
    try {
      final downloadService = Get.find<DownloadService>();
      await downloadService.updateRemoteEntry(
        taskKey: entry.taskKey,
        entry: entry.entry,
      );
      SmartDialog.showToast('更新成功');
      await refresh();
    } catch (e) {
      SmartDialog.showToast('更新失败：$e');
    }
  }
}
