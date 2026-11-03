import 'package:cookmate/features/cooking/step_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 10, 31, 12);
  DateTime at(int s) => t0.add(Duration(seconds: s));

  test('chưa bắt đầu thì còn nguyên thời gian', () {
    final t = StepTimer(const Duration(minutes: 1));
    expect(t.isIdle, isTrue);
    expect(t.remaining(at(30)), const Duration(minutes: 1));
  });

  test('hẹn 1 phút, 20 giây sau còn 40 giây (quay lại màn hình vẫn đúng)', () {
    final t = StepTimer(const Duration(minutes: 1))..start(at(0));
    expect(t.remaining(at(20)), const Duration(seconds: 40));
    expect(t.isFinished(at(20)), isFalse);
  });

  test('tạm dừng giữ nguyên thời gian còn lại, tiếp tục chạy tiếp', () {
    final t = StepTimer(const Duration(minutes: 1))
      ..start(at(0))
      ..pause(at(20));
    expect(t.remaining(at(500)), const Duration(seconds: 40));
    t.start(at(500));
    expect(t.remaining(at(510)), const Duration(seconds: 30));
  });

  test('hết giờ', () {
    final t = StepTimer(const Duration(seconds: 10))..start(at(0));
    expect(t.isFinished(at(10)), isTrue);
    expect(t.remaining(at(99)), Duration.zero);
  });

  test('đặt lại', () {
    final t = StepTimer(const Duration(seconds: 10))
      ..start(at(0))
      ..reset();
    expect(t.isIdle, isTrue);
    expect(t.remaining(at(5)), const Duration(seconds: 10));
  });

  test('bắt đầu lại sau khi hết giờ chạy lại từ đầu', () {
    final t = StepTimer(const Duration(seconds: 10))..start(at(0));
    t.start(at(15));
    expect(t.remaining(at(20)), const Duration(seconds: 5));
  });
}
