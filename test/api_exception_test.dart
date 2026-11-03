import 'package:cookmate/core/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _response(int status, Object? data) {
  final req = RequestOptions(path: '/x');
  return DioException(
    requestOptions: req,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: req, statusCode: status, data: data),
  );
}

void main() {
  test('dùng thông báo {"error"} của server', () {
    final e = ApiException.fromDio(_response(409, {'error': 'Email đã được đăng ký'}));
    expect(e.statusCode, 409);
    expect(e.message, 'Email đã được đăng ký');
  });

  test('không có body thì dùng câu mặc định theo mã lỗi', () {
    expect(ApiException.fromDio(_response(429, null)).message, contains('quá nhanh'));
    expect(ApiException.fromDio(_response(500, '')).message, contains('Máy chủ'));
  });

  test('mất kết nối là lỗi mạng, không có statusCode', () {
    final e = ApiException.fromDio(DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.connectionError,
    ));
    expect(e.isNetworkError, isTrue);
    expect(e.message, contains('Không kết nối được máy chủ'));
  });
}
