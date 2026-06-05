import 'dart:async';

import 'package:PiliPlus/models/user/info.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';

class AccountService extends GetxService {
  final RxString face = ''.obs;
  final RxBool isLogin = false.obs;

  @override
  void onInit() {
    super.onInit();
    UserInfoData? userInfo = Pref.userInfoCache;
    if (userInfo != null) {
      face.value = userInfo.face ?? '';
      isLogin.value = true;
    } else {
      face.value = '';
      // Fall back to actual credentials so a valid session whose profile cache
      // is missing still reports as logged in (the profile is refreshed lazily).
      isLogin.value = Accounts.main.isLogin;
    }
  }
}

mixin AccountMixin on GetLifeCycleBase {
  StreamSubscription<bool>? _listener;

  AccountService get accountService => Get.find<AccountService>();

  void onChangeAccount(bool isLogin);

  @override
  void onInit() {
    super.onInit();
    _listener = accountService.isLogin.listen(onChangeAccount);
  }

  @override
  void onClose() {
    _listener?.cancel();
    _listener = null;
    super.onClose();
  }
}
