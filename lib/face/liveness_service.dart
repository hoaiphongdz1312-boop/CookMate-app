/// Chống ảnh giả bằng nháy mắt (hàm thuần, không phụ thuộc camera).
///
/// Người dùng phải nháy mắt 1 lần trong [window] kể từ khung hình đầu tiên:
/// mắt MỞ → NHẮM (cả hai mắt) → MỞ lại. Xác suất mở mắt lấy từ
/// `Face.leftEyeOpenProbability` / `rightEyeOpenProbability` của ML Kit.
enum LivenessState { waiting, passed, failed }

class BlinkLivenessDetector {
  BlinkLivenessDetector({
    this.window = const Duration(seconds: 3),
    this.openThreshold = 0.6,
    this.closedThreshold = 0.3,
  });

  final Duration window;

  /// Trung bình 2 mắt ≥ ngưỡng này thì coi là mở.
  final double openThreshold;

  /// Cả 2 mắt < ngưỡng này thì coi là nhắm.
  final double closedThreshold;

  DateTime? _start;
  bool _sawOpen = false;
  bool _sawClosed = false;
  LivenessState _state = LivenessState.waiting;

  LivenessState get state => _state;

  /// Thời gian còn lại của lượt thử (để hiện đếm ngược).
  Duration remaining(DateTime now) {
    final start = _start;
    if (start == null) return window;
    final left = window - now.difference(start);
    return left.isNegative ? Duration.zero : left;
  }

  /// Đưa vào xác suất mở mắt của một khung hình. Khung thiếu dữ liệu bị bỏ qua
  /// (nhưng vẫn tính thời gian).
  LivenessState addFrame(double? leftOpen, double? rightOpen, DateTime now) {
    if (_state != LivenessState.waiting) return _state;
    _start ??= now;
    if (now.difference(_start!) > window) {
      return _state = LivenessState.failed;
    }
    if (leftOpen == null || rightOpen == null) return _state;

    final open = (leftOpen + rightOpen) / 2 >= openThreshold;
    final closed = leftOpen < closedThreshold && rightOpen < closedThreshold;
    if (!_sawOpen) {
      if (open) _sawOpen = true;
    } else if (!_sawClosed) {
      if (closed) _sawClosed = true;
    } else if (open) {
      _state = LivenessState.passed;
    }
    return _state;
  }

  void reset() {
    _start = null;
    _sawOpen = false;
    _sawClosed = false;
    _state = LivenessState.waiting;
  }
}
