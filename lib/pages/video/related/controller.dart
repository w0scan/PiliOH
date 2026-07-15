import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/search/search_type.dart';
import 'package:PiliPlus/models/model_hot_video_item.dart';
import 'package:PiliPlus/models/model_owner.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/pages/common/common_list_controller.dart';
import 'package:PiliPlus/utils/recommend_filter.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class RelatedController
    extends CommonListController<List<HotVideoItemModel>?, HotVideoItemModel> {
  RelatedController({this.autoQuery = true});
  String bvid = Get.arguments['bvid'];
  String? title = Get.arguments['title'];
  final bool autoQuery;

  /// 搜索结果在列表中的起始索引，null表示无搜索结果
  final searchStartIndex = Rxn<int>();

  /// 分割线的GlobalKey，用于滚动定位
  final GlobalKey dividerKey = GlobalKey(debugLabel: 'searchDivider');

  /// 是否有搜索结果
  bool get hasSearchResults => searchStartIndex.value != null;

  @override
  void onInit() {
    super.onInit();
    if (autoQuery) {
      queryData();
    }
  }

  @override
  Future<LoadingState<List<HotVideoItemModel>?>> customGetData() =>
      VideoHttp.relatedVideoList(bvid: bvid);

  @override
  Future<void> queryData([bool isRefresh = true]) async {
    await super.queryData(isRefresh);
    if (isRefresh && title != null && title!.isNotEmpty) {
      await _searchByTitle();
    }
  }

  Future<void> _searchByTitle() async {
    final res = await SearchHttp.searchByType<SearchVideoData>(
      searchType: SearchType.video,
      keyword: title!,
      page: 1,
      onSuccess: (_) {},
    );
    if (res case Success(:final response)) {
      final searchItems = response.list;
      if (searchItems == null || searchItems.isEmpty) return;

      final hotItems = searchItems
          .where((item) => item.bvid != bvid)
          .map(_searchToHotVideo)
          .toList();

      final filteredItems = RecommendFilter.applyFilterToRelatedVideos
          ? hotItems.where((i) => !RecommendFilter.filterAll(i)).toList()
          : hotItems;

      if (filteredItems.isEmpty) return;

      if (loadingState.value case Success(:final response)) {
        searchStartIndex.value = response?.length ?? 0;
        response?.addAll(filteredItems);
        loadingState.refresh();
      }
    }
  }

  /// 滚动到搜索结果分割线位置
  void scrollToSearchResults() {
    final context = dividerKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.0,
      );
    }
  }

  HotVideoItemModel _searchToHotVideo(SearchVideoItemModel search) {
    final searchOwner = search.owner;
    final searchStat = search.stat;
    return HotVideoItemModel.fromJson({
      'aid': search.aid,
      'bvid': search.bvid,
      'pic': search.cover,
      'title': search.title,
      'pubdate': search.pubdate,
      'ctime': search.ctime,
      'desc': search.desc,
      'duration': search.duration,
      'owner': {
        'mid': searchOwner.mid,
        'name': searchOwner.name,
        'face': searchOwner is Owner ? searchOwner.face : null,
      },
      'stat': {
        'view': searchStat.view,
        'danmaku': searchStat.danmu,
        'like': searchStat.like,
        'reply': searchStat is SearchStat ? searchStat.reply : null,
        'favorite': searchStat is SearchStat ? searchStat.favorite : null,
      },
      'redirect_url': search.redirectUrl,
    });
  }
}