/// Cấu hình kết nối server. Đây là NƠI DUY NHẤT đặt địa chỉ server.
///
/// Mặc định dùng cho máy ảo Android: 10.0.2.2 là địa chỉ của laptop nhìn từ máy ảo.
/// Đổi khi chạy (không cần sửa code):
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:5255/api
/// Xem docs/KET_NOI_SERVER.md.
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://cookmate2026-001-site1.dtempurl.com/api',
  );

  /// Web client ID của Google (dùng để lấy idToken cho server, không phải Android client ID):
  ///   flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxx.apps.googleusercontent.com
  /// Xem docs/GOOGLE_LOGIN.md.
  static const String googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// Đường dẫn tương đối của ảnh tải lên (vd. /uploads/abc.jpg) thành URL đầy đủ của server.
  static String fileUrl(String path) {
    final base = Uri.parse(apiBaseUrl);
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: path,
    ).toString();
  }

  // Máy thật qua USB/Wi-Fi chậm và chập chờn hơn máy ảo, nên nới timeout hơn một chút.
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
