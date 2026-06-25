import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/msg.dart';
import 'package:PiliPlus/models_new/msg/msg_reply/data.dart';
import 'package:PiliPlus/models_new/msg/msg_reply/item.dart';
import 'package:PiliPlus/pages/common/cursor_list_controller.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class ReplyMeController
    extends CursorListController<MsgReplyData, MsgReplyItem> {
  @override
  List<MsgReplyItem>? getDataList(MsgReplyData response) {
    if (response.cursor?.isEnd == true) {
      isEnd = true;
    }
    cursor = response.cursor?.id;
    cursorTime = response.cursor?.time;
    return response.items;
  }

  @override
  Future<LoadingState<MsgReplyData>> customGetData() =>
      MsgHttp.msgFeedReplyMe(cursor: cursor, cursorTime: cursorTime);

  Future<void> onRemove(dynamic id, int index) async {
    try {
      final res = await MsgHttp.delMsgfeed(1, id);
      if (res.isSuccess) {
        loadingState
          ..value.data!.removeAt(index)
          ..refresh();
        SmartDialog.showToast('删除成功');
      } else {
        res.toast();
      }
    } catch (_) {}
  }
}
