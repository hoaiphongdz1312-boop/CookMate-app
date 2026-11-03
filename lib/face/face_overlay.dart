import 'package:flutter/material.dart';

import 'image_utils.dart';

/// Vẽ khung quanh các khuôn mặt lên trên preview camera.
class FaceOverlayPainter extends CustomPainter {
  FaceOverlayPainter({
    required this.faces,
    required this.imageSize,
    required this.mirror,
    required this.color,
  });

  /// Khung mặt trong tọa độ ảnh ĐỨNG (như ML Kit trả về).
  final List<Rect> faces;

  /// Kích thước ảnh ĐỨNG mà [faces] tham chiếu tới.
  final Size imageSize;

  /// `true` với camera trước (preview bị lật gương).
  final bool mirror;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color;
    for (final face in faces) {
      final rect = uprightRectToCanvas(face, imageSize, size, mirror: mirror);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(FaceOverlayPainter old) =>
      old.faces != faces ||
      old.imageSize != imageSize ||
      old.mirror != mirror ||
      old.color != color;
}
