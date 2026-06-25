import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/http/api.dart';
import 'package:PiliPlus/http/init.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/response_handler.dart';
import 'package:PiliPlus/models/common/fav_order_type.dart';
import 'package:PiliPlus/models_new/fav/fav_article/data.dart';
import 'package:PiliPlus/models_new/fav/fav_detail/data.dart';
import 'package:PiliPlus/models_new/fav/fav_folder/data.dart';
import 'package:PiliPlus/models_new/fav/fav_folder/list.dart';
import 'package:PiliPlus/models_new/fav/fav_note/list.dart';
import 'package:PiliPlus/models_new/fav/fav_pgc/data.dart';
import 'package:PiliPlus/models_new/fav/fav_topic/data.dart';
import 'package:PiliPlus/models_new/space/space_cheese/data.dart';
import 'package:PiliPlus/models_new/space/space_fav/data.dart';
import 'package:PiliPlus/models_new/sub/sub_detail/data.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/app_sign.dart';
import 'package:dio/dio.dart';

abstract final class FavHttp {
  static Future<LoadingState<void>> favFavFolder(Object mediaId) async {
    final res = await Request().post(
      Api.favFavFolder,
      data: HttpUtils.csrfData({'media_id': mediaId}),
      options: HttpUtils.formOptions,
    );
    return res.handleVoid();
  }

  static Future<LoadingState<void>> unfavFavFolder(Object mediaId) async {
    final res = await Request().post(
      Api.unfavFavFolder,
      data: HttpUtils.csrfData({'media_id': mediaId}),
      options: HttpUtils.formOptions,
    );
    return res.handleVoid();
  }

  static Future<LoadingState<FavDetailData>> userFavFolderDetail({
    required int mediaId,
    required int pn,
    required int ps,
    String keyword = '',
    FavOrderType order = FavOrderType.mtime,
    int type = 0,
  }) async {
    final res = await Request().get(
      Api.favResourceList,
      queryParameters: {
        'media_id': mediaId,
        'pn': pn,
        'ps': ps,
        'keyword': keyword,
        'order': order.name,
        'type': type,
        'tid': 0,
        'platform': 'web',
      },
    );
    return res.handle((data) => FavDetailData.fromJson(data));
  }

  // 取消订阅
  static Future<LoadingState<void>> cancelSub({
    required int id,
    required int type,
  }) async {
    final res = type == 11
        ? await Request().post(
            Api.unfavFolder,
            data: HttpUtils.csrfData({'media_id': id}),
            options: HttpUtils.formOptions,
          )
        : await Request().post(
            Api.unfavSeason,
            data: HttpUtils.csrfData({
              'platform': 'web',
              'season_id': id,
            }),
            options: HttpUtils.formOptions,
          );
    return res.handleVoid();
  }

  static Future<LoadingState<SubDetailData>> favSeasonList({
    required int id,
    required int pn,
    required int ps,
  }) async {
    final res = await Request().get(
      Api.favSeasonList,
      queryParameters: {
        'season_id': id,
        'ps': ps,
        'pn': pn,
      },
    );
    return res.handle((data) => SubDetailData.fromJson(data));
  }

  static Future<LoadingState<SpaceCheeseData>> favPugv({
    required int mid,
    required int page,
  }) async {
    final res = await Request().get(
      Api.favPugv,
      queryParameters: {
        'mid': mid,
        'ps': 20,
        'pn': page,
        'web_location': 333.1387,
      },
    );
    return res.handle((data) => SpaceCheeseData.fromJson(data));
  }

  static Future<LoadingState<void>> addFavPugv(Object seasonId) async {
    final res = await Request().post(
      Api.addFavPugv,
      data: HttpUtils.csrfData({'season_id': seasonId}),
      options: HttpUtils.formOptions,
    );
    return res.handleVoid();
  }

  static Future<LoadingState<void>> delFavPugv(Object seasonId) async {
    final res = await Request().post(
      Api.delFavPugv,
      data: HttpUtils.csrfData({'season_id': seasonId}),
      options: HttpUtils.formOptions,
    );
    return res.handleVoid();
  }

  static Future<LoadingState<FavTopicData>> favTopic({
    required int page,
  }) async {
    final res = await Request().get(
      Api.favTopicList,
      queryParameters: {
        'page_size': 24,
        'page_num': page,
        'web_location': 333.1387,
      },
    );
    return res.handle((data) => FavTopicData.fromJson(data));
  }

  static Future<LoadingState<void>> addFavTopic(Object topicId) async {
    final res = await Request().post(
      Api.addFavTopic,
      data: HttpUtils.csrfData({'topic_id': topicId}),
      options: HttpUtils.formOptions,
    );
    return res.handleVoid();
  }

  static Future<LoadingState<void>> delFavTopic(Object topicId) async {
    final res = await Request().post(
      Api.delFavTopic,
      data: HttpUtils.csrfData({'topic_id': topicId}),
      options: HttpUtils.formOptions,
    );
    return res.handleVoid();
  }

  static Future<LoadingState<void>> likeTopic(
    Object topicId,
    bool isLike,
  ) async {
    final res = await Request().post(
      Api.likeTopic,
      data: HttpUtils.csrfData({
        'action': isLike ? 'cancel_like' : 'like',
        'up_mid': Accounts.main.mid,
        'topic_id': topicId,
        'business': 'topic',
      }),
      options: HttpUtils.formOptions,
    );
    return res.handleVoid();
  }

  static Future<LoadingState<FavArticleData>> favArticle({
    required int page,
  }) async {
    final res = await Request().get(
      Api.favArticle,
      queryParameters: {
        'page_size': 20,
        'page': page,
      },
    );
    return res.handle((data) => FavArticleData.fromJson(data));
  }

  static Future<LoadingState<void>> addFavArticle({
    required Object id,
  }) async {
    final res = await Request().post(
      Api.addFavArticle,
      data: HttpUtils.csrfData({'id': id}),
      options: HttpUtils.formOptions,
    );
    return res.handleVoid();
  }

  static Future<LoadingState<void>> delFavArticle({
    required Object id,
  }) async {
    final res = await Request().post(
      Api.delFavArticle,
      data: HttpUtils.csrfData({'id': id}),
      options: HttpUtils.formOptions,
    );
    return res.handleVoid();
  }

  static Future<LoadingState<List<FavNoteItemModel>?>> userNoteList({
    required int page,
  }) async {
    final res = await Request().get(
      Api.userNoteList,
      queryParameters: {
        'pn': page,
        'ps': 10,
        'csrf': Accounts.main.csrf,
      },
    );
    if (res.data['code'] == 0) {
      List<FavNoteItemModel>? list = (res.data['data']?['list'] as List?)
          ?.map((e) => FavNoteItemModel.fromJson(e))
          .toList();
      return Success(list);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<List<FavNoteItemModel>?>> noteList({
    required int page,
  }) async {
    final res = await Request().get(
      Api.noteList,
      queryParameters: {
        'pn': page,
        'ps': 10,
        'csrf': Accounts.main.csrf,
      },
    );
    if (res.data['code'] == 0) {
      List<FavNoteItemModel>? list = (res.data['data']?['list'] as List?)
          ?.map((e) => FavNoteItemModel.fromJson(e))
          .toList();
      return Success(list);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<void>> delNote({
    required bool isPublish,
    required String noteIds,
  }) async {
    final res = await Request().post(
      isPublish ? Api.delPublishNote : Api.delNote,
      data: HttpUtils.csrfData({
        isPublish ? 'cvids' : 'note_ids': noteIds,
      }),
      options: HttpUtils.formOptions,
    );
    return res.handleVoid();
  }

  static Future<LoadingState<FavPgcData>> favPgc({
    required int type,
    required int pn,
    int? followStatus,
    Object? mid,
  }) async {
    final res = await Request().get(
      Api.favPgc,
      queryParameters: {
        'vmid': mid ?? Accounts.main.mid,
        'type': type,
        'follow_status': ?followStatus,
        'pn': pn,
      },
    );
    return res.handle((data) => FavPgcData.fromJson(data));
  }

  // 收藏夹
  static Future<LoadingState<FavFolderData>> userfavFolder({
    required int pn,
    required int ps,
    required dynamic mid,
  }) async {
    final res = await Request().get(
      Api.userFavFolder,
      queryParameters: {
        'pn': pn,
        'ps': ps,
        'up_mid': mid,
      },
    );
    if (res.data['code'] == 0) {
      return Success(FavFolderData.fromJson(res.data['data']));
    } else {
      return Error(res.data['message'] ?? '账号未登录');
    }
  }

  static Future<LoadingState<void>> sortFavFolder({
    required String sort,
  }) async {
    Map<String, dynamic> data = {
      'sort': sort,
      'csrf': Accounts.main.csrf,
    };
    AppSign.appSign(data);
    final res = await Request().post(
      Api.sortFavFolder,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<void>> sortFav({
    required Object mediaId,
    required String sort,
  }) async {
    Map<String, dynamic> data = {
      'media_id': mediaId,
      'sort': sort,
      'csrf': Accounts.main.csrf,
    };
    AppSign.appSign(data);
    final res = await Request().post(
      Api.sortFav,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    if (res.data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(res.data['message']);
    }
  }

  static Future<LoadingState<void>> cleanFav({
    required Object mediaId,
  }) async {
    final res = await Request().post(
      Api.cleanFav,
      data: HttpUtils.csrfData({
        'media_id': mediaId,
        'platform': 'web',
      }),
      options: HttpUtils.formOptions,
    );
    return res.handleVoid();
  }

  static Future<LoadingState<void>> deleteFolder({
    required String mediaIds,
  }) async {
    final res = await Request().post(
      Api.deleteFolder,
      data: HttpUtils.csrfData({
        'media_ids': mediaIds,
        'platform': 'web',
      }),
      options: HttpUtils.formOptions,
    );
    return res.handleVoid();
  }

  static Future<LoadingState<FavFolderInfo>> addOrEditFolder({
    required bool isAdd,
    dynamic mediaId,
    required String title,
    required int privacy,
    required String cover,
    required String intro,
  }) async {
    final res = await Request().post(
      isAdd ? Api.addFolder : Api.editFolder,
      data: HttpUtils.csrfData({
        'title': title,
        'intro': intro,
        'privacy': privacy,
        'cover': cover.isNotEmpty ? Uri.encodeFull(cover) : cover,
        'media_id': ?mediaId,
      }),
      options: HttpUtils.formOptions,
    );
    return res.handle((data) => FavFolderInfo.fromJson(data));
  }

  static Future<LoadingState<FavFolderInfo>> favFolderInfo({
    required Object mediaId,
  }) async {
    final res = await Request().get(
      Api.favFolderInfo,
      queryParameters: {
        'media_id': mediaId,
      },
    );
    return res.handle((data) => FavFolderInfo.fromJson(data));
  }

  static Future<LoadingState<void>> seasonFav({
    required bool isFav,
    required dynamic seasonId,
  }) async {
    final res = await Request().post(
      isFav ? Api.unfavSeason : Api.favSeason,
      data: HttpUtils.csrfData({
        'platform': 'web',
        'season_id': seasonId,
      }),
      options: HttpUtils.formOptions,
    );
    return res.handleVoid();
  }

  static Future<LoadingState<List<SpaceFavData>?>> spaceFav({
    required int mid,
  }) async {
    final params = {
      'build': 8430300,
      'version': '8.43.0',
      'c_locale': 'zh_CN',
      'channel': 'master',
      'mobi_app': 'android',
      'platform': 'android',
      's_locale': 'zh_CN',
      'statistics': Constants.statisticsApp,
      'up_mid': mid,
    };
    final res = await Request().get(
      Api.spaceFav,
      queryParameters: params,
      options: Options(
        headers: {
          'bili-http-engine': 'cronet',
          'user-agent': Constants.userAgentApp,
        },
      ),
    );
    return res.handle(
      (data) => (data as List?)?.map((e) => SpaceFavData.fromJson(e)).toList(),
    );
  }

  static Future<LoadingState<void>> communityAction({
    required Object opusId,
    required Object action,
  }) async {
    final res = await Request().post(
      Api.communityAction,
      queryParameters: {
        'csrf': Accounts.main.csrf,
      },
      data: {
        "entity": {
          "object_id_str": opusId,
          "type": {"biz": 2},
        },
        "action": action, // 3 fav, 4 unfav
      },
    );
    return res.handleVoid();
  }

  // （取消）收藏
  static Future<LoadingState<void>> favVideo({
    required String resources,
    String? addIds,
    String? delIds,
  }) async {
    final res = await Request().post(
      Api.favVideo,
      data: HttpUtils.csrfData({
        'resources': resources,
        'add_media_ids': addIds ?? '',
        'del_media_ids': delIds ?? '',
      }),
      options: HttpUtils.formOptions,
    );
    return res.handleVoid();
  }

  // （取消）收藏
  static Future<LoadingState<void>> unfavAll({
    required Object rid,
    required Object type,
  }) async {
    final res = await Request().post(
      Api.unfavAll,
      data: HttpUtils.csrfData({'rid': rid, 'type': type}),
      options: HttpUtils.formOptions,
    );
    return res.handleVoid();
  }

  static Future<LoadingState<void>> copyOrMoveFav({
    required bool isCopy,
    required bool isFav,
    required dynamic srcMediaId,
    required dynamic tarMediaId,
    dynamic mid,
    required String resources,
  }) async {
    final res = await Request().post(
      isFav
          ? isCopy
                ? Api.copyFav
                : Api.moveFav
          : isCopy
          ? Api.copyToview
          : Api.moveToview,
      data: HttpUtils.csrfData({
        'src_media_id': ?srcMediaId,
        'tar_media_id': tarMediaId,
        'mid': ?mid,
        'resources': resources,
        'platform': 'web',
      }),
      options: HttpUtils.formOptions,
    );
    return res.handleVoid();
  }

  static Future<LoadingState<FavFolderData>> allFavFolders(Object mid) async {
    final res = await Request().get(
      Api.favFolder,
      queryParameters: {'up_mid': mid},
    );
    return res.handle((data) => FavFolderData.fromJson(data));
  }

  // 查看视频被收藏在哪个文件夹
  static Future<LoadingState<FavFolderData>> videoInFolder({
    dynamic mid,
    dynamic rid,
    dynamic type,
  }) async {
    final res = await Request().get(
      Api.favFolder,
      queryParameters: {
        'up_mid': mid,
        'rid': rid,
        'type': ?type,
      },
    );
    return res.handle((data) => FavFolderData.fromJson(data));
  }
}
