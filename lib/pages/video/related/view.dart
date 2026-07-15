import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/model_hot_video_item.dart';
import 'package:PiliPlus/pages/video/related/controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class RelatedVideoPanel extends StatefulWidget {
  const RelatedVideoPanel({super.key, required this.heroTag});
  final String heroTag;
  @override
  State<RelatedVideoPanel> createState() => _RelatedVideoPanelState();
}

class _RelatedVideoPanelState extends State<RelatedVideoPanel> with GridMixin {
  late final RelatedController _relatedController;

  @override
  void initState() {
    super.initState();
    _relatedController = Get.putOrFind(
      RelatedController.new,
      tag: widget.heroTag,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.only(top: 7, bottom: 100),
      sliver: Obx(() => _buildBody(_relatedController.loadingState.value)),
    );
  }

  Widget _buildBody(LoadingState<List<HotVideoItemModel>?> loadingState) {
    return switch (loadingState) {
      Loading() => gridSkeleton,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? _buildGrid(response)
            : const SliverToBoxAdapter(),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _relatedController.onReload,
      ),
    };
  }

  Widget _buildGrid(List<HotVideoItemModel> response) {
    final searchIndex = _relatedController.searchStartIndex;
    if (searchIndex == null || searchIndex >= response.length) {
      // 无搜索结果，直接显示全部相关视频
      return SliverGrid.builder(
        gridDelegate: gridDelegate,
        itemBuilder: (context, index) => VideoCardH(
          videoItem: response[index],
          onRemove: () => _relatedController.loadingState
            ..value.data!.removeAt(index)
            ..refresh(),
        ),
        itemCount: response.length,
      );
    }

    // 有搜索结果：相关视频 + 分割线 + 搜索结果
    return SliverMainAxisGroup(
      slivers: [
        // 相关视频
        SliverGrid.builder(
          gridDelegate: gridDelegate,
          itemBuilder: (context, index) => VideoCardH(
            videoItem: response[index],
            onRemove: () => _relatedController.loadingState
              ..value.data!.removeAt(index)
              ..refresh(),
          ),
          itemCount: searchIndex,
        ),
        // 分割线
        SliverToBoxAdapter(
          key: _relatedController.dividerKey,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Expanded(child: Divider(height: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '搜索结果',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                const Expanded(child: Divider(height: 1)),
              ],
            ),
          ),
        ),
        // 搜索结果
        SliverGrid.builder(
          gridDelegate: gridDelegate,
          itemBuilder: (context, index) {
            final actualIndex = searchIndex + index;
            return VideoCardH(
              videoItem: response[actualIndex],
              onRemove: () => _relatedController.loadingState
                ..value.data!.removeAt(actualIndex)
                ..refresh(),
            );
          },
          itemCount: response.length - searchIndex,
        ),
      ],
    );
  }
}
