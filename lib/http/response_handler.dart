import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:dio/dio.dart';

extension ResponseHandler on Response {
  LoadingState<T> handle<T>(T Function(dynamic data) onSuccess) {
    if (data['code'] == 0) {
      return Success(onSuccess(data['data']));
    } else {
      return Error(data['message']);
    }
  }

  LoadingState<void> handleVoid() {
    if (data['code'] == 0) {
      return const Success(null);
    } else {
      return Error(data['message']);
    }
  }
}

abstract final class HttpUtils {
  static Options get formOptions =>
      Options(contentType: Headers.formUrlEncodedContentType);

  static Map<String, dynamic> csrfData(Map<String, dynamic> data) => {
    ...data,
    'csrf': Accounts.main.csrf,
  };
}
