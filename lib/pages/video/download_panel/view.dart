import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/models/common/badge_type.dart';
import 'package:PiliPlus/models/common/stat_type.dart';
import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/models_new/pgc/pgc_info_model/episode.dart' as pgc;
import 'package:PiliPlus/models_new/pgc/pgc_info_model/result.dart';
import 'package:PiliPlus/models_new/video/video_detail/data.dart';
import 'package:PiliPlus/models_new/video/video_detail/episode.dart' as ugc;
import 'package:PiliPlus/models_new/video/video_detail/page.dart';
import 'package:PiliPlus/pages/download/view.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/widgets/page.dart';
import 'package:PiliPlus/services/download/download_service.dart';
import 'package:PiliPlus/services/download/remote_cache_client.dart';
import 'package:PiliPlus/services/download/remote_cache_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class DownloadPanel extends StatefulWidget {
  const DownloadPanel({
    super.key,
    required this.index,
    this.pgcItem,
    this.videoDetail,
    required this.episodes,
    required this.scrollController,
    required this.videoDetailController,
    required this.heroTag,
    this.ugcIntroController,
    required this.cidSet,
  });

  final int index;
  final PgcInfoModel? pgcItem;
  final VideoDetailData? videoDetail;
  final List<ugc.BaseEpisodeItem> episodes;
  final ScrollController scrollController;
  final VideoDetailController videoDetailController;
  final String heroTag;
  final UgcIntroController? ugcIntroController;
  final Set<int> cidSet;

  @override
  State<DownloadPanel> createState() => _DownloadPanelState();
}

class _DownloadPanelState extends State<DownloadPanel> {
  final DownloadService _downloadService = Get.find<DownloadService>();
  final RemoteCacheService _remoteService =
      Get.isRegistered<RemoteCacheService>()
      ? Get.find<RemoteCacheService>()
      : Get.put(RemoteCacheService());
  final ListController _listController = ListController();

  late final cidSet = widget.cidSet;
  VideoQuality _quality = VideoQuality.fromCode(Pref.defaultVideoQa);
  bool _isRemote = false;

  Set<int> get _remoteCidSet => _remoteService.cidSet;

  bool get _isRemoteAvailable {
    final client = RemoteCacheClient.fromSettings();
    return client != null;
  }

  @override
  void initState() {
    super.initState();
    if (_isRemoteAvailable) {
      _remoteService.refresh();
    }
    if (widget.index != -1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _listController.jumpToItem(
          index: widget.index,
          scrollController: widget.scrollController,
          alignment: 0,
        );
      });
    }
  }

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dividerColor = theme.colorScheme.outline.withValues(alpha: 0.2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildHeader(theme),
        _buildBody(theme),
        Divider(height: 1, color: dividerColor),
        _buildFooter(theme, dividerColor),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final textStyle = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 0, 12),
      child: Row(
        spacing: 16,
        children: [
          Text(
            '最高画质',
            style: textStyle,
          ),
          Builder(
            builder: (context) => PopupMenuButton<VideoQuality>(
              initialValue: _quality,
              onSelected: (value) {
                _quality = value;
                (context as Element).markNeedsBuild();
              },
              itemBuilder: (context) => VideoQuality.values
                  .map(
                    (e) => PopupMenuItem(
                      value: e,
                      child: Text(e.desc),
                    ),
                  )
                  .toList(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _quality.desc,
                      style: const TextStyle(height: 1),
                      strutStyle: const StrutStyle(height: 1, leading: 0),
                    ),
                    Icon(
                      size: 18,
                      Icons.keyboard_arrow_down,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('本地')),
              ButtonSegment(value: true, label: Text('远端')),
            ],
            selected: {_isRemote},
            onSelectionChanged: (value) {
              final wantRemote = value.first;
              if (wantRemote && !_isRemoteAvailable) {
                SmartDialog.showToast('请先配置远程缓存服务器');
                return;
              }
              setState(() => _isRemote = wantRemote);
              if (_isRemote) {
                _remoteService.refresh();
              }
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                theme.textTheme.labelSmall,
              ),
            ),
          ),
          if (kDebugMode || PlatformUtils.isMobile) ...[
            StreamBuilder(
              stream: Connectivity().onConnectivityChanged,
              builder: (context, snapshot) {
                if (snapshot.data case final data?) {
                  final network = data.contains(ConnectivityResult.wifi)
                      ? 'WIFI'
                      : '数据';
                  return Text('当前网络：$network', style: textStyle);
                }
                return const SizedBox.shrink();
              },
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final episodes = widget.episodes;
    return Expanded(
      child: Material(
        type: MaterialType.transparency,
        child: CustomScrollView(
          controller: widget.scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 100),
              sliver: SuperSliverList.builder(
                itemCount: episodes.length,
                listController: _listController,
                itemBuilder: (context, index) {
                  final episode = episodes[index];
                  final hasParts =
                      episode is ugc.EpisodeItem && episode.pages!.length > 1;
                  Widget child = _buildItem(
                    theme: theme,
                    index: index,
                    hasParts: hasParts,
                    episode: episode,
                    isCurrentIndex: index == widget.index,
                  );
                  if (hasParts) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        child,
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          child: PagesPanel(
                            list: episode.pages,
                            cover: episode.arc?.pic,
                            heroTag: widget.heroTag,
                            ugcIntroController: widget.ugcIntroController!,
                            bvid: episode.bvid ?? IdUtils.av2bv(episode.aid!),
                            cidSet: _isRemote ? _remoteCidSet : cidSet,
                            onDownload: (Part part) => _onDownload(
                              index: index,
                              episode: part,
                              parent: episode,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return child;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  late final int? vipStatus = Pref.userInfoCache?.vipStatus;
  @pragma('vm:notify-debugger-on-exception')
  bool _onDownload({
    required int index,
    required ugc.BaseEpisodeItem episode,
    bool isFromList = false,
    bool isDownloadAll = false,
    ugc.EpisodeItem? parent,
  }) {
    final cid = episode.cid;
    // on download
    if (cid == null) {
      SmartDialog.showToast('null cid');
      return false;
    }

    final alreadyCached = _isRemote
        ? _remoteCidSet.contains(cid)
        : cidSet.contains(cid);
    if (alreadyCached) {
      if (kDebugMode) {
        SmartDialog.showToast('downloaded');
      }
      return false;
    }

    if (kReleaseMode && episode.badge == '会员' && Accounts.mainEqVideo) {
      if (vipStatus != 1) {
        if (!isDownloadAll) {
          SmartDialog.showToast('需要大会员');
        }
        return false;
      }
    }

    if (episode is ugc.EpisodeItem) {
      final pages = episode.pages!;
      if (pages.length > 1) {
        if (isFromList && kDebugMode) {
          SmartDialog.showToast('hasParts');
        }
        if (isDownloadAll) {
          for (int i = 0; i < pages.length; i++) {
            _onDownload(
              index: i,
              episode: pages[i],
              parent: episode,
            );
          }
          return true;
        }
        return false;
      }
    }

    try {
      if (_isRemote) {
        _onRemoteDownload(index: index, episode: episode, parent: parent);
      } else {
        switch (episode) {
          case Part part:
            _downloadService.downloadVideo(
              part,
              parent == null ? widget.videoDetail : null,
              parent,
              _quality,
            );
            break;
          case ugc.EpisodeItem episode:
            _downloadService.downloadVideo(
              episode.pages!.first,
              null,
              episode,
              _quality,
            );
            break;
          case pgc.EpisodeItem episode:
            _downloadService.downloadBangumi(
              index,
              widget.pgcItem!,
              episode,
              _quality,
            );
            break;
        }
      }
      if (!_isRemote) {
        cidSet.add(cid);
      }
      return true;
    } catch (e, s) {
      Utils.reportError(e, s);
      SmartDialog.showToast(e.toString());
    }
    return false;
  }

  Future<void> _submitRemoteDownload({
    required int index,
    required ugc.BaseEpisodeItem episode,
    ugc.EpisodeItem? parent,
  }) async {
    switch (episode) {
      case Part part:
        await _downloadService.remoteDownloadVideo(
          part,
          parent == null ? widget.videoDetail : null,
          parent,
          _quality,
        );
      case ugc.EpisodeItem ep:
        await _downloadService.remoteDownloadVideo(
          ep.pages!.first,
          null,
          ep,
          _quality,
        );
      case pgc.EpisodeItem ep:
        await _downloadService.remoteDownloadBangumi(
          index,
          widget.pgcItem!,
          ep,
          _quality,
        );
    }
  }

  Future<void> _onRemoteDownload({
    required int index,
    required ugc.BaseEpisodeItem episode,
    ugc.EpisodeItem? parent,
  }) async {
    try {
      await _submitRemoteDownload(
        index: index,
        episode: episode,
        parent: parent,
      );
      await _remoteService.refresh();
      if (mounted) setState(() {});
      SmartDialog.showToast('远端缓存任务已创建');
    } catch (e, s) {
      Utils.reportError(e, s);
      SmartDialog.showToast('远端缓存失败：$e');
    }
  }

  Widget _buildItem({
    required ThemeData theme,
    required int index,
    required bool hasParts,
    required bool isCurrentIndex,
    required ugc.BaseEpisodeItem episode,
  }) {
    late String title;
    num? duration;
    int? pubdate;
    int? view;
    int? danmaku;
    bool? isCharging;
    int? cid;

    String? cover;
    bool? cacheWidth;

    switch (episode) {
      case Part part:
        cid = part.cid;
        cover = part.firstFrame ?? widget.videoDetail?.pic;
        title = part.part ?? widget.videoDetail!.title!;
        duration = part.duration;
        pubdate = part.ctime;
        cacheWidth = part.dimension?.cacheWidth;
        break;
      case ugc.EpisodeItem item:
        cid = item.cid;
        title = item.title!;
        if (item.arc case final arc?) {
          cover = arc.pic;
          duration = arc.duration;
          pubdate = arc.pubdate;
          if (arc.stat case final stat?) {
            view = stat.view;
            danmaku = stat.danmaku;
          }
          cacheWidth = arc.dimension?.cacheWidth;
        }
        if (item.attribute == 8) {
          isCharging = true;
        }
        break;
      case pgc.EpisodeItem item:
        cid = item.cid;
        title = item.showTitle ?? item.title!;
        cover = item.cover;
        if (item.from == 'pugv') {
          duration = item.duration;
          view = item.play;
        } else {
          duration = item.duration == null ? null : item.duration! ~/ 1000;
        }
        pubdate = item.pubTime;
        cacheWidth = item.dimension?.cacheWidth;
        break;
    }
    late final primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: SizedBox(
        height: 110,
        child: Builder(
          builder: (context) {
            return Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () {
                  if (_onDownload(
                    index: index,
                    episode: episode,
                    isFromList: true,
                  )) {
                    (context as Element).markNeedsBuild();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Style.safeSpace,
                    vertical: 5,
                  ),
                  child: Row(
                    spacing: 10,
                    children: [
                      if (cover?.isNotEmpty == true)
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            NetworkImgLayer(
                              src: cover,
                              width: 160,
                              height: 100,
                              cacheWidth: cacheWidth,
                            ),
                            if (duration != null && duration > 0)
                              PBadge(
                                text: DurationUtils.formatDuration(duration),
                                right: 6.0,
                                bottom: 6.0,
                                type: PBadgeType.gray,
                              ),
                            if (isCharging == true)
                              const PBadge(
                                text: '充电专属',
                                top: 6,
                                right: 6,
                                type: PBadgeType.error,
                              )
                            else if (episode.badge != null)
                              PBadge(
                                text: episode.badge,
                                top: 6,
                                right: 6,
                                type: switch (episode.badge) {
                                  '预告' => PBadgeType.gray,
                                  '限免' => PBadgeType.free,
                                  _ => PBadgeType.primary,
                                },
                              ),
                          ],
                        )
                      else if (isCurrentIndex)
                        Image.asset(
                          Assets.livingStatic,
                          color: primary,
                          height: 12,
                          cacheHeight: 12.cacheSize(context),
                          semanticLabel: '正在播放：',
                        ),
                      Expanded(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    textAlign: TextAlign.start,
                                    style: TextStyle(
                                      fontSize:
                                          theme.textTheme.bodyMedium!.fontSize,
                                      height: 1.42,
                                      letterSpacing: 0.3,
                                      fontWeight: isCurrentIndex
                                          ? FontWeight.bold
                                          : null,
                                      color: isCurrentIndex ? primary : null,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (pubdate != null)
                                  Text(
                                    DateFormatUtils.format(pubdate),
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1,
                                      color: theme.colorScheme.outline,
                                      overflow: TextOverflow.clip,
                                    ),
                                  ),
                                const SizedBox(height: 2),
                                Row(
                                  spacing: 8,
                                  children: [
                                    if (view != null)
                                      StatWidget(
                                        value: view,
                                        type: StatType.play,
                                      ),
                                    if (danmaku != null)
                                      StatWidget(
                                        value: danmaku,
                                        type: StatType.danmaku,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            if (!hasParts &&
                                (_isRemote
                                    ? _remoteCidSet.contains(cid)
                                    : cidSet.contains(cid)))
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Icon(
                                  size: 13,
                                  color: theme.colorScheme.secondary.withValues(
                                    alpha: 0.8,
                                  ),
                                  FontAwesomeIcons.circleDown,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFooter(ThemeData theme, Color dividerColor) {
    final targetLabel = _isRemote ? '远端' : '本地';
    return Container(
      color: theme.hoverColor,
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Row(
        children: [
          _buildBottomBtn(
            text: '缓存全部到$targetLabel',
            onTap: () {
              showConfirmDialog(
                context: context,
                title: Text('确定缓存全部到$targetLabel？'),
                onConfirm: () {
                  if (_isRemote) {
                    _downloadAllRemote();
                  } else {
                    for (int i = 0; i < widget.episodes.length; i++) {
                      _onDownload(
                        index: i,
                        episode: widget.episodes[i],
                        isDownloadAll: true,
                      );
                    }
                  }
                  if (mounted) setState(() {});
                },
              );
            },
          ),
          SizedBox(
            height: 20,
            child: VerticalDivider(
              width: 1,
              color: dividerColor,
            ),
          ),
          _buildBottomBtn(
            text: '查看缓存',
            onTap: () => Navigator.of(context).push(
              GetPageRoute(page: () => const DownloadPage()),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAllRemote() async {
    final episodes = widget.episodes;
    int submitted = 0;
    int failed = 0;
    for (int i = 0; i < episodes.length; i++) {
      final episode = episodes[i];
      final cid = episode.cid;
      if (cid == null) continue;
      if (_remoteCidSet.contains(cid)) continue;
      if (kReleaseMode && episode.badge == '会员' && Accounts.mainEqVideo) {
        if (vipStatus != 1) continue;
      }
      // Handle multi-part episodes
      if (episode is ugc.EpisodeItem && episode.pages!.length > 1) {
        for (int j = 0; j < episode.pages!.length; j++) {
          final part = episode.pages![j];
          if (_remoteCidSet.contains(part.cid)) {
            continue;
          }
          try {
            await _submitRemoteDownload(
              index: j,
              episode: part,
              parent: episode,
            );
            submitted++;
          } catch (e) {
            failed++;
          }
        }
        continue;
      }
      try {
        await _submitRemoteDownload(index: i, episode: episode);
        submitted++;
      } catch (e) {
        failed++;
      }
    }
    await _remoteService.refresh();
    if (mounted) {
      setState(() {});
      if (failed > 0) {
        SmartDialog.showToast('完成 $submitted 个，失败 $failed 个');
      } else if (submitted > 0) {
        SmartDialog.showToast('已提交 $submitted 个远端缓存任务');
      }
    }
  }

  Widget _buildBottomBtn({
    required String text,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 40,
          width: double.infinity,
          child: Center(
            child: Text(
              text,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
