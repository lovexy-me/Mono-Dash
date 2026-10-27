/// 网络层自定义异常体系。
///
/// 拦截器与 `DioClient` 统一把底层 `DioException` 转换为这里的子类，
/// 上层 Repository / UI 只需关心这些语义化异常。
library;

/// 所有网络异常的基类。
sealed class AppNetworkException implements Exception {
  const AppNetworkException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => '$runtimeType($statusCode): $message';
}

/// 网络不可达 / 超时 / DNS 失败等连接层错误。
class NetworkConnectionException extends AppNetworkException {
  const NetworkConnectionException(super.message);
}

/// 401 或 MD5 鉴权失败。
class AuthException extends AppNetworkException {
  const AuthException(super.message, {super.statusCode});
}

/// 5xx 服务端错误。
class ServerException extends AppNetworkException {
  const ServerException(super.message, {super.statusCode});
}

/// 4xx 客户端错误（非 401）。
class HttpException extends AppNetworkException {
  const HttpException(super.message, {super.statusCode});
}

/// HTTP 200 但业务层返回 `code != 200`。
class ApiBusinessException extends AppNetworkException {
  const ApiBusinessException(int code, super.message, {this.errorCode})
    : super(statusCode: code);

  final String? errorCode;
}

/// 响应体格式不符合预期（缺少 data 字段等）。
class ApiFormatException extends AppNetworkException {
  const ApiFormatException(super.message);
}
