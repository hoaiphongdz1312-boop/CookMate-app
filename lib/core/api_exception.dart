import 'package:dio/dio.dart';

/// Lỗi gọi API đã được dịch sang thông báo tiếng Việt để hiện cho người dùng.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;

  /// null nếu không nhận được phản hồi (mất mạng, server tắt, hết thời gian chờ)
  final int? statusCode;

  bool get isNetworkError => statusCode == null;

  factory ApiException.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException('Máy chủ phản hồi quá lâu. Kiểm tra mạng rồi thử lại.');
      case DioExceptionType.connectionError:
        return ApiException(
            'Không kết nối được máy chủ. Kiểm tra server đã chạy và địa chỉ kết nối.');
      case DioExceptionType.cancel:
        return ApiException('Yêu cầu đã bị hủy.');
      default:
        break;
    }

    final status = e.response?.statusCode;
    if (status == null) {
      return ApiException('Có lỗi kết nối, vui lòng thử lại.');
    }

    // Server luôn trả { "error": "..." } bằng tiếng Việt (KE_HOACH_v2 mục 5)
    final data = e.response?.data;
    if (data is Map && data['error'] is String && (data['error'] as String).isNotEmpty) {
      return ApiException(data['error'] as String, statusCode: status);
    }

    return ApiException(_defaultMessage(status), statusCode: status);
  }

  static String _defaultMessage(int status) => switch (status) {
        400 => 'Dữ liệu gửi lên không hợp lệ.',
        401 => 'Bạn chưa đăng nhập hoặc phiên đã hết hạn.',
        404 => 'Không tìm thấy dữ liệu.',
        409 => 'Dữ liệu bị trùng.',
        429 => 'Bạn thao tác quá nhanh, vui lòng đợi một chút.',
        >= 500 => 'Máy chủ đang gặp lỗi, vui lòng thử lại sau.',
        _ => 'Có lỗi xảy ra (mã $status).',
      };

  @override
  String toString() => message;
}
