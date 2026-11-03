import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// =============================================================================
// XỬ LÝ ẢNH CAMERA ANDROID
//
// Có 3 hệ tọa độ cần phân biệt:
//
// 1. Ảnh THÔ từ cảm biến (sensor): kích thước W×H do camera trả về (thường
//    nằm ngang, ví dụ 640×480). Cảm biến được gắn xoay so với màn hình một góc
//    `CameraDescription.sensorOrientation` (camera trước thường là 270°,
//    camera sau thường là 90°).
//
// 2. Ảnh ĐỨNG (upright): ảnh thô sau khi xoay THEO CHIỀU KIM ĐỒNG HỒ một góc
//    `rotation` (xem [rotationForCamera]). Với rotation 90/270 thì kích thước
//    thành H×W. ML Kit nhận ảnh thô + rotation và trả `Face.boundingBox` trong
//    hệ tọa độ ảnh ĐỨNG này. Lưu ý: ảnh đứng KHÔNG bị lật gương — đây là ảnh
//    "như người khác nhìn vào mình".
//
// 3. Màn hình preview: `CameraPreview` của camera trước hiển thị ảnh ĐÃ LẬT
//    GƯƠNG (giống soi gương, giơ tay phải thì thấy tay bên phải màn hình).
//    Vì vậy khi vẽ khung mặt lên preview của camera trước phải lật trục x
//    (xem [uprightRectToCanvas]).
//
// Còn khi cắt mặt cho MobileFaceNet thì dùng ảnh ĐỨNG, KHÔNG lật gương, cho
// cả lúc đăng ký lẫn lúc nhận diện. Quan trọng là hai lúc phải giống hệt nhau
// thì vector mới so sánh được.
// =============================================================================

/// Góc xoay tương ứng với hướng cầm máy (độ).
const Map<DeviceOrientation, int> _deviceOrientationDegrees = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

/// Góc cần xoay ảnh thô (theo chiều kim đồng hồ) để ảnh đứng thẳng.
///
/// Công thức lấy theo ví dụ chính thức của google_mlkit_commons:
/// - camera trước: (sensorOrientation + gócMáy) % 360
///   (camera trước quay ngược với camera sau nên CỘNG góc máy)
/// - camera sau:   (sensorOrientation − gócMáy + 360) % 360
///
/// App khóa màn hình dọc nên gócMáy thường là 0 → rotation = sensorOrientation.
InputImageRotation? rotationForCamera(
  CameraDescription camera,
  DeviceOrientation deviceOrientation,
) {
  final deviceDegrees = _deviceOrientationDegrees[deviceOrientation];
  if (deviceDegrees == null) return null;
  final sensor = camera.sensorOrientation;
  final degrees = camera.lensDirection == CameraLensDirection.front
      ? (sensor + deviceDegrees) % 360
      : (sensor - deviceDegrees + 360) % 360;
  return InputImageRotationValue.fromRawValue(degrees);
}

/// Tạo [InputImage] cho ML Kit từ frame camera.
///
/// Camera được mở với `ImageFormatGroup.nv21`. Plugin camera_android_camerax
/// gộp 3 plane YUV_420_888 thành MỘT plane NV21 liền mạch,
/// `bytesPerRow == width`. ML Kit trên Android chỉ nhận NV21, nên frame có
/// định dạng khác được bỏ qua (trả null) thay vì làm crash app.
InputImage? inputImageFromCameraImage(
  CameraImage image,
  InputImageRotation rotation,
) {
  final format = InputImageFormatValue.fromRawValue(image.format.raw);
  if (format != InputImageFormat.nv21 || image.planes.length != 1) {
    return null;
  }
  final plane = image.planes.first;
  return InputImage.fromBytes(
    bytes: plane.bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: InputImageFormat.nv21,
      bytesPerRow: plane.bytesPerRow,
    ),
  );
}

/// Kích thước ảnh ĐỨNG: xoay 90°/270° thì đổi chỗ rộng và cao.
Size uprightSize(int rawWidth, int rawHeight, InputImageRotation rotation) {
  final swap = rotation == InputImageRotation.rotation90deg ||
      rotation == InputImageRotation.rotation270deg;
  return swap
      ? Size(rawHeight.toDouble(), rawWidth.toDouble())
      : Size(rawWidth.toDouble(), rawHeight.toDouble());
}

/// Đổi tọa độ (u, v) trên ảnh ĐỨNG về tọa độ (x, y) trên ảnh THÔ W×H.
///
/// Ảnh đứng = ảnh thô xoay theo chiều kim đồng hồ một góc [rotation]:
/// - 0°:   (u, v) = (x, y)
/// - 90°:  (u, v) = (H−1−y, x)   → x = v,       y = H−1−u
/// - 180°: (u, v) = (W−1−x, H−1−y) → x = W−1−u, y = H−1−v
/// - 270°: (u, v) = (y, W−1−x)   → x = W−1−v,   y = u
(double, double) uprightToRaw(
  double u,
  double v,
  int rawWidth,
  int rawHeight,
  InputImageRotation rotation,
) {
  return switch (rotation) {
    InputImageRotation.rotation0deg => (u, v),
    InputImageRotation.rotation90deg => (v, rawHeight - 1 - u),
    InputImageRotation.rotation180deg => (rawWidth - 1 - u, rawHeight - 1 - v),
    InputImageRotation.rotation270deg => (rawWidth - 1 - v, u),
  };
}

/// Mở rộng khung mặt thêm [margin] mỗi phía, ép về tỉ lệ [aspect] (rộng/cao)
/// của input model, rồi dời/co cho nằm gọn trong ảnh [bounds].
Rect squareCropRect(Rect face, Size bounds, {double margin = 0.1, double aspect = 1}) {
  var w = face.width * (1 + 2 * margin);
  var h = face.height * (1 + 2 * margin);
  // Ép tỉ lệ: lấy cạnh lớn hơn để không cắt mất phần mặt.
  if (w / h > aspect) {
    h = w / aspect;
  } else {
    w = h * aspect;
  }
  // Không vượt quá ảnh.
  final scale = math.min(1.0, math.min(bounds.width / w, bounds.height / h));
  w *= scale;
  h *= scale;
  final left = (face.center.dx - w / 2).clamp(0.0, bounds.width - w);
  final top = (face.center.dy - h / 2).clamp(0.0, bounds.height - h);
  return Rect.fromLTWH(left, top, w, h);
}

/// Cắt vùng mặt từ frame NV21 và tạo tensor input cho MobileFaceNet.
///
/// - [nv21]: buffer NV21 W×H, Y liền mạch (W·H byte) rồi tới các cặp V,U
///   xen kẽ, mỗi cặp dùng chung cho khối 2×2 pixel.
/// - [crop]: vùng cần cắt, trong tọa độ ảnh ĐỨNG (không lật gương).
/// - Trả về Float32List theo thứ tự [outH][outW][RGB], đã chuẩn hóa
///   (giá trị − [mean]) / [std].
///
/// Không tạo ảnh RGB trung gian: với mỗi pixel đầu ra, tính ngược vị trí trên
/// ảnh thô, lấy Y bằng nội suy song tuyến tính (bilinear) và U/V theo điểm gần
/// nhất (chroma vốn chỉ có nửa độ phân giải), rồi đổi sang RGB (BT.601
/// full-range như camera Android). Chỉ duyệt outW×outH điểm (112×112 ≈ 12.5k)
/// nên nhanh, không làm giật UI.
Float32List cropNv21ToModelInput({
  required Uint8List nv21,
  required int width,
  required int height,
  required InputImageRotation rotation,
  required Rect crop,
  required int outWidth,
  required int outHeight,
  required double mean,
  required double std,
}) {
  final out = Float32List(outWidth * outHeight * 3);
  final frameSize = width * height;
  final stepX = crop.width / outWidth;
  final stepY = crop.height / outHeight;
  var o = 0;
  for (var oy = 0; oy < outHeight; oy++) {
    // Tâm pixel đầu ra, quy về tọa độ ảnh đứng.
    final v = crop.top + (oy + 0.5) * stepY - 0.5;
    for (var ox = 0; ox < outWidth; ox++) {
      final u = crop.left + (ox + 0.5) * stepX - 0.5;
      final (fx, fy) = uprightToRaw(u, v, width, height, rotation);
      final x = fx.clamp(0.0, width - 1.0);
      final y = fy.clamp(0.0, height - 1.0);

      // Bilinear trên kênh Y.
      final x0 = x.floor(), y0 = y.floor();
      final x1 = math.min(x0 + 1, width - 1), y1 = math.min(y0 + 1, height - 1);
      final ax = x - x0, ay = y - y0;
      final yTop = nv21[y0 * width + x0] * (1 - ax) + nv21[y0 * width + x1] * ax;
      final yBot = nv21[y1 * width + x0] * (1 - ax) + nv21[y1 * width + x1] * ax;
      final lum = yTop * (1 - ay) + yBot * ay;

      // Chroma: NV21 lưu V trước, U sau.
      final cx = x.round() >> 1, cy = y.round() >> 1;
      final uvIndex = frameSize + cy * width + cx * 2;
      final vv = nv21[math.min(uvIndex, nv21.length - 2)] - 128.0;
      final uu = nv21[math.min(uvIndex + 1, nv21.length - 1)] - 128.0;

      final r = (lum + 1.402 * vv).clamp(0.0, 255.0);
      final g = (lum - 0.344136 * uu - 0.714136 * vv).clamp(0.0, 255.0);
      final b = (lum + 1.772 * uu).clamp(0.0, 255.0);

      out[o++] = (r - mean) / std;
      out[o++] = (g - mean) / std;
      out[o++] = (b - mean) / std;
    }
  }
  return out;
}

/// Đổi khung mặt từ tọa độ ảnh ĐỨNG sang tọa độ khung preview [canvas].
///
/// Preview của camera trước bị lật gương nên phải lật trục x ([mirror] = true).
Rect uprightRectToCanvas(Rect r, Size upright, Size canvas, {required bool mirror}) {
  final sx = canvas.width / upright.width;
  final sy = canvas.height / upright.height;
  final left = mirror ? canvas.width - r.right * sx : r.left * sx;
  return Rect.fromLTWH(left, r.top * sy, r.width * sx, r.height * sy);
}
