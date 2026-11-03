import 'package:flutter_test/flutter_test.dart';

import 'package:cookmate/face/liveness_service.dart';

void main() {
  final t0 = DateTime(2026);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  test('mở → nhắm → mở trong 3 giây thì đạt', () {
    final d = BlinkLivenessDetector();
    expect(d.addFrame(0.9, 0.9, at(0)), LivenessState.waiting);
    expect(d.addFrame(0.1, 0.1, at(300)), LivenessState.waiting);
    expect(d.addFrame(0.9, 0.8, at(500)), LivenessState.passed);
  });

  test('ảnh tĩnh (mắt luôn mở) thì hết giờ và thất bại', () {
    final d = BlinkLivenessDetector();
    for (var ms = 0; ms <= 3000; ms += 100) {
      d.addFrame(0.95, 0.95, at(ms));
    }
    expect(d.addFrame(0.95, 0.95, at(3100)), LivenessState.failed);
  });

  test('chỉ nhắm một mắt (nháy một bên) không tính', () {
    final d = BlinkLivenessDetector();
    d.addFrame(0.9, 0.9, at(0));
    d.addFrame(0.1, 0.9, at(200));
    expect(d.addFrame(0.9, 0.9, at(400)), LivenessState.waiting);
  });

  test('nhắm sẵn từ đầu rồi mở chưa đủ, phải nhắm lại', () {
    final d = BlinkLivenessDetector();
    d.addFrame(0.1, 0.1, at(0));
    d.addFrame(0.9, 0.9, at(200));
    expect(d.state, LivenessState.waiting);
    d.addFrame(0.1, 0.1, at(400));
    expect(d.addFrame(0.9, 0.9, at(600)), LivenessState.passed);
  });

  test('khung thiếu xác suất mắt bị bỏ qua', () {
    final d = BlinkLivenessDetector();
    d.addFrame(0.9, 0.9, at(0));
    d.addFrame(null, null, at(100));
    d.addFrame(0.1, 0.1, at(200));
    expect(d.addFrame(0.9, 0.9, at(300)), LivenessState.passed);
  });

  test('nháy sau 3 giây thì không tính', () {
    final d = BlinkLivenessDetector();
    d.addFrame(0.9, 0.9, at(0));
    d.addFrame(0.1, 0.1, at(2900));
    expect(d.addFrame(0.9, 0.9, at(3200)), LivenessState.failed);
  });

  test('reset bắt đầu lượt mới và đếm ngược lại', () {
    final d = BlinkLivenessDetector();
    d.addFrame(0.9, 0.9, at(0));
    d.addFrame(0.9, 0.9, at(3500));
    expect(d.state, LivenessState.failed);
    d.reset();
    expect(d.state, LivenessState.waiting);
    expect(d.remaining(at(4000)), const Duration(seconds: 3));
  });
}
