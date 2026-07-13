import 'dart:async';

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/appbar/appbar.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/dialog/simple_dialog_option.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/select_mask.dart';
import 'package:PiliPlus/models/common/video/source_type.dart';
import 'package:PiliPlus/models/common/badge_type.dart';
import 'package:PiliPlus/models_new/download/download_info.dart';
import 'package:PiliPlus/pages/download/controller.dart';
import 'package:PiliPlus/pages/download/detail/view.dart';
import 'package:PiliPlus/pages/download/detail/widgets/item.dart';
import 'package:PiliPlus/pages/download/search/view.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/services/download/remote_cache_client.dart';
import 'package:PiliPlus/services/download/remote_cache_service.dart';
import 'package:PiliPlus/utils/cache_manager.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart'
    hide SliverGridDelegateWithMaxCrossAxisExtent;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> with GridMixin {
  final _downloadService = Get.find<DownloadService>();
  final _controller = Get.put(DownloadPageController());
  final _progress = ChangeNotifier();
  final _remote = Get.put(RemoteCacheService());
  bool showRemote = false;

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = MediaQuery.viewPaddingOf(context);
    return Obx(() {
      final enableMultiSelect = _controller.enableMultiSelect.value;
      return popScope(
        canPop: !enableMultiSelect,
        onPopInvokedWithResult: (didPop, result) {
          if (enableMultiSelect) {
            _controller.handleSelect();
          }
        },
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: MultiSelectAppBarWidget(
            ctr: _controller,
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () async {
                  final future = [
                    for (final page in _controller.allChecked)
                      for (final e in page.entries)
                        _downloadService.downloadDanmaku(
                          entry: e,
                          isUpdate: true,
                        ),
                  ];
                  _controller.handleSelect();
                  final res = await Future.wait(future);
                  if (res.every((e) => e)) {
                    SmartDialog.showToast('更新成功');
                  } else {
                    SmartDialog.showToast('更新失败');
                  }
                },
                child: Text(
                  '更新',
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
              ),
            ],
            child: AppBar(
              title: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('本地')),
                  ButtonSegment(value: true, label: Text('远端')),
                ],
                selected: {showRemote},
                onSelectionChanged: (value) {
                  setState(() => showRemote = value.first);
                  if (showRemote) _remote.refresh();
                },
              ),
              actions: [
                if (showRemote)
                  IconButton(
                    tooltip: '刷新',
                    onPressed: _remote.refresh,
                    icon: const Icon(Icons.refresh),
                  )
                else ...[
                  IconButton(
                    tooltip: '搜索',
                    onPressed: () async {
                      await _downloadService.waitForInitialization;
                      if (!mounted) return;
                      Get.to(DownloadSearchPage(progress: _progress));
                    },
                    icon: const Icon(Icons.search),
                  ),
                  IconButton(
                    tooltip: '多选',
                    onPressed: () {
                      if (enableMultiSelect) {
                        _controller.handleSelect();
                      } else {
                        _controller.enableMultiSelect.value = true;
                      }
                    },
                    icon: const Icon(Icons.edit_note),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          body: showRemote
              ? _buildRemoteBody(theme, padding)
              : Padding(
                  padding: EdgeInsets.only(
                    left: padding.left,
                    right: padding.right,
                  ),
                  child: CustomScrollView(
                    slivers: [
                      Obx(() {
                        final entry =
                            _downloadService.waitDownloadQueue.firstWhereOrNull(
                              (e) => e.cid == _downloadService.curCid,
                            ) ??
                            _downloadService.waitDownloadQueue.firstOrNull;
                        if (entry != null) {
                          return SliverMainAxisGroup(
                            slivers: [
                              SliverPadding(
                                padding: const EdgeInsets.only(
                                  left: 12,
                                  bottom: 7,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: Text(
                                    '正在缓存 (${_downloadService.waitDownloadQueue.length})',
                                  ),
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: SizedBox(
                                  height: 110,
                                  child: DetailItem(
                                    entry: entry,
                                    progress: _progress,
                                    downloadService: _downloadService,
                                    showTitle: true,
                                    isCurr: true,
                                    controller: _controller,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }
                        return const SliverToBoxAdapter();
                      }),
                      Obx(() {
                        if (_controller.pages.isNotEmpty) {
                          return SliverMainAxisGroup(
                            slivers: [
                              SliverPadding(
                                padding: EdgeInsets.only(
                                  left: 12,
                                  bottom: 7,
                                  top:
                                      _downloadService.waitDownloadQueue.isEmpty
                                      ? 0
                                      : 7,
                                ),
                                sliver: const SliverToBoxAdapter(
                                  child: Text('已缓存视频'),
                                ),
                              ),
                              SliverGrid.builder(
                                gridDelegate: gridDelegate,
                                itemBuilder: (context, index) {
                                  final item = _controller.pages[index];
                                  if (item.entries.length == 1) {
                                    final entry = item.entries.first;
                                    return DetailItem(
                                      entry: entry,
                                      progress: _progress,
                                      downloadService: _downloadService,
                                      showTitle: true,
                                      onDelete: () {
                                        _downloadService.deleteDownload(
                                          entry: entry,
                                          removeList: true,
                                        );
                                        GStorage.watchProgress.delete(
                                          entry.cid.toString(),
                                        );
                                      },
                                      checked: item.checked,
                                      onSelect: (_) =>
                                          _controller.onSelect(item),
                                      controller: _controller,
                                    );
                                  }
                                  return _buildItem(
                                    theme,
                                    item,
                                    enableMultiSelect,
                                  );
                                },
                                itemCount: _controller.pages.length,
                              ),
                            ],
                          );
                        }
                        if (_downloadService.waitDownloadQueue.isNotEmpty) {
                          return const SliverToBoxAdapter();
                        }
                        return const HttpError();
                      }),
                      SliverToBoxAdapter(
                        child: SizedBox(height: padding.bottom + 100),
                      ),
                    ],
                  ),
                ),
        ),
      );
    });
  }

  Widget _buildRemoteBody(ThemeData theme, EdgeInsets padding) {
    return Obx(() {
      if (_remote.loading.value && _remote.entries.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_remote.error case final error?) {
        return Center(child: Text(error));
      }
      return RefreshIndicator(
        onRefresh: _remote.refresh,
        child: ListView.builder(
          padding: EdgeInsets.fromLTRB(12, 12, 12, padding.bottom + 80),
          itemCount: _remote.entries.length,
          itemBuilder: (context, index) {
            final item = _remote.entries[index];
            final entry = item.entry;
            final task = item.task;
            final status = task?['status']?.toString() ?? 'unknown';
            final client = RemoteCacheClient.fromSettings()!;
            return Card(
              child: ListTile(
                leading: Image.network(
                  client.fileUrl(item.taskKey, 'cover.jpg'),
                  headers: client.mediaHeaders,
                  width: 96,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.video_file),
                ),
                title: Text(entry.showTitle),
                subtitle: Text('$status  ${entry.qualityPithyDescription}'),
                onTap: status == 'completed'
                    ? () => PageUtils.toVideoPage(
                        aid: entry.avid,
                        cid: entry.cid,
                        cover: entry.cover,
                        title: entry.showTitle,
                        isVertical: entry.pageData?.isVertical ?? false,
                        extraArguments: {
                          'sourceType': SourceType.file,
                          'entry': entry,
                          'remoteVideoUrl': client.fileUrl(
                            item.taskKey,
                            'video.m4s',
                          ),
                          'remoteAudioUrl': entry.hasDashAudio
                              ? client.fileUrl(item.taskKey, 'audio.m4s')
                              : null,
                          'remoteHeaders': client.mediaHeaders,
                        },
                      )
                    : null,
                trailing: PopupMenuButton<String>(
                  onSelected: (action) async {
                    if (action == 'delete') {
                      await _remote.delete(item);
                    } else {
                      await _remote.action(item, action);
                    }
                  },
                  itemBuilder: (_) => [
                    if (status == 'downloading' || status == 'queued')
                      const PopupMenuItem(value: 'pause', child: Text('暂停')),
                    if (status == 'paused')
                      const PopupMenuItem(value: 'resume', child: Text('继续')),
                    if (status == 'failed')
                      const PopupMenuItem(value: 'retry', child: Text('重试')),
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ),
            );
          },
        ),
      );
    });
  }

  Widget _buildItem(
    ThemeData theme,
    DownloadPageInfo pageInfo,
    bool enableMultiSelect,
  ) {
    void onLongPress() => enableMultiSelect
        ? null
        : showDialog(
            context: context,
            builder: (context) => SimpleDialog(
              clipBehavior: Clip.hardEdge,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                DialogOption(
                  onPressed: () {
                    Get.back();
                    showConfirmDialog(
                      context: context,
                      title: const Text('确定删除？'),
                      onConfirm: () async {
                        await GStorage.watchProgress.deleteAll(
                          pageInfo.entries.map((e) => e.cid.toString()),
                        );
                        _downloadService.deletePage(
                          pageDirPath: pageInfo.dirPath,
                        );
                      },
                    );
                  },
                  child: const Text('删除', style: TextStyle(fontSize: 14)),
                ),
                DialogOption(
                  onPressed: () async {
                    Get.back();
                    final res = await Future.wait(
                      pageInfo.entries.map(
                        (e) => _downloadService.downloadDanmaku(
                          entry: e,
                          isUpdate: true,
                        ),
                      ),
                    );
                    if (res.every((e) => e)) {
                      SmartDialog.showToast('更新成功');
                    } else {
                      SmartDialog.showToast('更新失败');
                    }
                  },
                  child: const Text('更新弹幕', style: TextStyle(fontSize: 14)),
                ),
              ],
            ),
          );
    final first = pageInfo.entries.first;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {
          if (_controller.enableMultiSelect.value) {
            _controller.onSelect(pageInfo);
            return;
          }
          Get.to(
            DownloadDetailPage(
              pageId: pageInfo.pageId,
              title: pageInfo.title,
              progress: _progress,
            ),
          );
        },
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Style.safeSpace,
            vertical: 5,
          ),
          child: Row(
            spacing: 10,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AspectRatio(
                    aspectRatio: Style.aspectRatio,
                    child: LayoutBuilder(
                      builder: (context, constraints) => NetworkImgLayer(
                        src: pageInfo.cover,
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                      ),
                    ),
                  ),
                  PBadge(
                    text: '${pageInfo.entries.length}个视频',
                    right: 6.0,
                    bottom: 6.0,
                    isBold: false,
                    type: PBadgeType.gray,
                  ),
                  if (pageInfo.seasonType case final pgcType?)
                    PBadge(
                      text: switch (pgcType) {
                        -1 => '课程',
                        1 => '番剧',
                        2 => '电影',
                        3 => '纪录片',
                        4 => '国创',
                        5 => '电视剧',
                        7 => '综艺',
                        _ => null,
                      },
                      right: 6.0,
                      top: 6.0,
                    ),
                  Positioned.fill(
                    child: selectMask(theme.colorScheme, pageInfo.checked),
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        pageInfo.title,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                          fontSize: theme.textTheme.bodyMedium!.fontSize,
                          height: 1.42,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      crossAxisAlignment: .end,
                      mainAxisAlignment: .spaceBetween,
                      children: [
                        Text(
                          '${CacheManager.formatSize(pageInfo.entries.fold(0, (p, n) => p + n.totalBytes))}  ${first.ownerName ?? ""}',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.6,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        pageInfo.entries.first.moreBtn(theme.colorScheme),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
