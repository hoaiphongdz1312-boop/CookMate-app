import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'package:cookmate/face/image_utils.dart';

/// Ảnh thô 4×2 (W×H), Y của pixel (x, y) = 10·(y·4 + x) + 10, chroma xám (128).
///   hàng 0:  10  20  30  40
///   hàng 1:  50  60  70  80
const _w = 4, _h = 2;
Uint8List _nv21() {
  final bytes = Uint8List(_w * _h * 3 ~/ 2);
  for (var i = 0; i < _w * _h; i++) {
    bytes[i] = 10 * i + 10;
  }
  bytes.fillRange(_w * _h, bytes.length, 128);
  return bytes;
}

/// Cắt toàn bộ ảnh đứng, giữ nguyên kích thước → đọc được giá trị Y theo
/// đúng thứ tự pixel của ảnh đứng.
List<int> _uprightLuma(InputImageRotation rotation) {
  final size = uprightSize(_w, _h, rotation);
  final out = cropNv21ToModelInput(
    nv21: _nv21(),
    width: _w,
    height: _h,
    rotation: rotation,
    crop: Offset.zero & size,
    outWidth: size.width.toInt(),
    outHeight: size.height.toInt(),
    mean: 0,
    std: 1,
  );
  // Chroma xám → R = G = B = Y; lấy kênh R.
  return [for (var i = 0; i < out.length; i += 3) out[i].round()];
}

void main() {
  group('uprightSize', () {
    test('xoay 90/270 thì đổi rộng và cao', () {
      expect(uprightSize(640, 480, InputImageRotation.rotation270deg),
          const Size(480, 640));
      expect(uprightSize(640, 480, InputImageRotation.rotation0deg),
          const Size(640, 480));
    });
  });

  group('cropNv21ToModelInput theo độ xoay (ảnh thô 4×2)', () {
    test('0°: giữ nguyên', () {
      expect(_uprightLuma(InputImageRotation.rotation0deg),
          [10, 20, 30, 40, 50, 60, 70, 80]);
    });

    test('90° theo chiều kim đồng hồ: cột trái (từ dưới lên) thành hàng đầu', () {
      // Ảnh đứng 2×4:  50 10 / 60 20 / 70 30 / 80 40
      expect(_uprightLuma(InputImageRotation.rotation90deg),
          [50, 10, 60, 20, 70, 30, 80, 40]);
    });

    test('180°: đảo ngược', () {
      expect(_uprightLuma(InputImageRotation.rotation180deg),
          [80, 70, 60, 50, 40, 30, 20, 10]);
    });

    test('270° (camera trước thường gặp): cột phải thành hàng đầu', () {
      // Ảnh đứng 2×4:  40 80 / 30 70 / 20 60 / 10 50
      expect(_uprightLuma(InputImageRotation.rotation270deg),
          [40, 80, 30, 70, 20, 60, 10, 50]);
    });

    test('chuẩn hóa (x − mean) / std', () {
      final out = cropNv21ToModelInput(
        nv21: _nv21(),
        width: _w,
        height: _h,
        rotation: InputImageRotation.rotation0deg,
        crop: const Rect.fromLTWH(0, 0, 1, 1),
        outWidth: 1,
        outHeight: 1,
        mean: 128,
        std: 128,
      );
      expect(out.length, 3);
      expect(out[0], closeTo((10 - 128) / 128, 1e-6));
    });
  });

  group('squareCropRect', () {
    test('ép vuông, nới lề và nằm trong ảnh', () {
      final r = squareCropRect(
        const Rect.fromLTWH(100, 100, 100, 150),
        const Size(480, 640),
        margin: 0.1,
      );
      expect(r.width, closeTo(r.height, 1e-9));
      expect(r.height, closeTo(150 * 1.2, 1e-9));
      expect(r.center.dx, closeTo(150, 1e-9));
    });

    test('mặt sát mép thì dời vào trong ảnh', () {
      final r = squareCropRect(
        const Rect.fromLTWH(0, 0, 100, 100),
        const Size(480, 640),
      );
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.top, greaterThanOrEqualTo(0));
    });

    test('mặt to hơn ảnh thì co lại vừa ảnh', () {
      final r = squareCropRect(
        const Rect.fromLTWH(0, 0, 500, 500),
        const Size(480, 640),
      );
      expect(r.width, lessThanOrEqualTo(480));
      expect(r.right, lessThanOrEqualTo(480 + 1e-9));
    });
  });

  group('uprightRectToCanvas', () {
    const upright = Size(480, 640);
    const canvas = Size(240, 320);
    const face = Rect.fromLTWH(0, 0, 100, 100);

    test('camera sau: chỉ co giãn', () {
      expect(uprightRectToCanvas(face, upright, canvas, mirror: false),
          const Rect.fromLTWH(0, 0, 50, 50));
    });

    test('camera trước: lật gương theo trục x', () {
      expect(uprightRectToCanvas(face, upright, canvas, mirror: true),
          const Rect.fromLTWH(190, 0, 50, 50));
    });
  });
}
