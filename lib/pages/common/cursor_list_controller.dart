import 'package:PiliPlus/pages/common/common_list_controller.dart';

abstract class CursorListController<R, T> extends CommonListController<R, T> {
  int? cursor;
  int? cursorTime;

  @override
  void onInit() {
    super.onInit();
    queryData();
  }

  @override
  Future<void> onRefresh() {
    cursor = null;
    cursorTime = null;
    return super.onRefresh();
  }
}
