import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'app_config.dart';
import 'token_storage.dart';

/// HTTP client dùng chung cho cả app. Mọi repository gọi API qua lớp này.
class ApiClient {
  ApiClient({
    required this._tokenStorage,
    required this._onUnauthorized,
    Dio? dio,
  }) : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              connectTimeout: AppConfig.connectTimeout,
              receiveTimeout: AppConfig.receiveTimeout,
              contentType: Headers.jsonContentType,
              responseType: ResponseType.json,
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _tokenStorage.read();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        // 401 khi đang có token nghĩa là token hết hạn/không hợp lệ: xóa và về màn đăng nhập.
        // 401 của chính login/face-login (chưa có token) thì để màn hình tự hiện lỗi.
        final hadToken = e.requestOptions.headers.containsKey('Authorization');
        if (e.response?.statusCode == 401 && hadToken) {
          await _tokenStorage.clear();
          await _onUnauthorized();
        }
        handler.next(e);
      },
    ));
  }

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final Future<void> Function() _onUnauthorized;

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get<T>(path, queryParameters: query), idempotent: true);

  Future<T> post<T>(String path, {Object? body}) =>
      _send(() => _dio.post<T>(path, data: body));

  Future<T> patch<T>(String path, {Object? body}) =>
      _send(() => _dio.patch<T>(path, data: body));

  Future<T> put<T>(String path, {Object? body}) =>
      _send(() => _dio.put<T>(path, data: body));

  Future<T> delete<T>(String path) => _send(() => _dio.delete<T>(path));

  /// Số lần thử lại khi mạng chập chờn (cáp USB/Wi-Fi rớt thoáng qua trên máy thật).
  static const int _maxRetries = 2;

  Future<T> _send<T>(Future<Response<T>> Function() request,
      {bool idempotent = false}) async {
    for (var attempt = 0;; attempt++) {
      try {
        final res = await request();
        return res.data as T;
      } on DioException catch (e) {
        if (attempt < _maxRetries && _canRetry(e, idempotent)) {
          await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
          continue;
        }
        throw ApiException.fromDio(e);
      }
    }
  }

  /// GET thử lại được với mọi lỗi mạng. Các method khác chỉ thử lại khi yêu cầu
  /// chắc chắn chưa tới server (không kết nối được), để tránh gửi trùng.
  bool _canRetry(DioException e, bool idempotent) {
    switch (e.type) {
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.connectionTimeout:
        // Không tới được server thì chờ lại 10s x 3 lần chỉ làm app treo lâu hơn.
        return false;
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return idempotent;
      default:
        return false;
    }
  }
}
