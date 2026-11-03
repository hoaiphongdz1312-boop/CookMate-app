/// Hằng số nhận diện khuôn mặt (lấy từ project cũ Nau_An_VIP).
///
/// Ngưỡng so khớp quyết định ở SERVER (appsettings, mục "Face"); app chỉ giữ
/// các hằng số lấy mẫu và kiểm tra chất lượng. Muốn đổi thì sửa trực tiếp ở đây.
abstract final class FaceConfig {
  /// Đường dẫn asset model MobileFaceNet.
  static const String faceModelAsset = 'assets/models/mobilefacenet.tflite';

  /// Chuẩn hóa pixel cho MobileFaceNet: (giá trị − mean) / std.
  static const double modelInputMean = 128.0;
  static const double modelInputStd = 128.0;

  /// Nới rộng khung mặt của ML Kit trước khi cắt (tỉ lệ mỗi phía).
  static const double faceCropMargin = 0.10;

  /// Mặt phải chiếm tối thiểu tỉ lệ này của bề ngang ảnh (đã xoay đứng).
  static const double minFaceWidthRatio = 0.30;

  /// Góc đầu tối đa (độ) để coi là "nhìn thẳng".
  static const double maxHeadEulerY = 12.0;
  static const double maxHeadEulerZ = 12.0;

  /// Đăng ký: số mẫu cần chụp (server nhận 3–5).
  static const int minRegisterSamples = 3;
  static const int maxRegisterSamples = 5;

  /// Khoảng cách tối thiểu giữa 2 lần tự chụp mẫu.
  static const Duration registerSampleInterval = Duration(milliseconds: 700);

  /// Đăng ký: mẫu mới phải giống các mẫu trước ít nhất chừng này.
  static const double registerSampleMinSimilarity = 0.75;

  /// Đăng nhập: số khung hình đạt chất lượng gửi lên (server yêu cầu đúng 3).
  static const int loginSamples = 3;

  /// Đăng nhập: số lần thử tối đa trước khi báo "Chưa nhận ra bạn".
  static const int maxLoginAttempts = 3;
}
