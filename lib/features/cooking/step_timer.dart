/// Bộ đếm giờ của một bước nấu. Lưu thời điểm KẾT THÚC thay vì đếm lùi số giây,
/// nên rời màn hình hoặc app ra nền rồi quay lại vẫn ra đúng thời gian còn lại.
/// Thuần Dart: thời gian hiện tại được truyền vào để test được.
class StepTimer {
  StepTimer(this.total);

  final Duration total;

  DateTime? _endAt;
  Duration? _pausedRemaining;

  bool get isRunning => _endAt != null;
  bool get isPaused => _pausedRemaining != null;
  bool get isIdle => !isRunning && !isPaused;

  Duration remaining(DateTime now) {
    final end = _endAt;
    if (end != null) {
      final left = end.difference(now);
      return left.isNegative ? Duration.zero : left;
    }
    return _pausedRemaining ?? total;
  }

  /// Đang chạy mà đã hết giờ.
  bool isFinished(DateTime now) => isRunning && remaining(now) == Duration.zero;

  /// Bắt đầu, hoặc tiếp tục nếu đang tạm dừng. Đã hết giờ thì bắt đầu lại từ đầu.
  void start(DateTime now) {
    if (isRunning && !isFinished(now)) return;
    final left = (isPaused ? _pausedRemaining! : total);
    _endAt = now.add(left == Duration.zero ? total : left);
    _pausedRemaining = null;
  }

  void pause(DateTime now) {
    if (!isRunning) return;
    _pausedRemaining = remaining(now);
    _endAt = null;
  }

  void reset() {
    _endAt = null;
    _pausedRemaining = null;
  }
}
