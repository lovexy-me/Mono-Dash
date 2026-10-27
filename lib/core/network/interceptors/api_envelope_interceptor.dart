import 'package:dio/dio.dart';

import '../network_exceptions.dart';

/// 识别 1Panel API envelope 中的业务失败，并转交给统一异常流程。
class ApiEnvelopeInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final failure = _failureFrom(response.data);
    if (failure == null) {
      handler.next(response);
      return;
    }

    handler.reject(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: ApiBusinessException(
          failure.code,
          failure.message,
          errorCode: failure.errorCode,
        ),
      ),
    );
  }

  _ApiEnvelopeFailure? _failureFrom(Object? payload) {
    if (payload is! Map) return null;

    final code = _codeOf(payload['code']);
    if (code == null || code == 200) return null;

    return _ApiEnvelopeFailure(
      code,
      _messageOf(payload),
      payload['errorCode']?.toString(),
    );
  }

  int? _codeOf(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  String _messageOf(Map<dynamic, dynamic> payload) {
    final message = payload['message'] ?? payload['msg'];
    final text = message?.toString().trim();
    return text == null || text.isEmpty ? '请求处理失败' : text;
  }
}

class _ApiEnvelopeFailure {
  const _ApiEnvelopeFailure(this.code, this.message, this.errorCode);

  final int code;
  final String message;
  final String? errorCode;
}
