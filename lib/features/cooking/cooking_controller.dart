import 'package:flutter/foundation.dart';

import '../recipes/recipe_models.dart';
import 'step_timer.dart';

/// Điều khiển chế độ nấu: bước hiện tại và bộ đếm giờ từng bước.
/// Màn hình chỉ gọi next/previous; F9 gắn [onStepChanged] để lưu tiến độ lên server.
class CookingController extends ChangeNotifier {
  CookingController(this.steps, {int startStep = 1, this.onStepChanged})
      : assert(steps.isNotEmpty),
        _index = (startStep - 1).clamp(0, steps.length - 1);

  final List<RecipeStep> steps;

  /// Gọi với số bước (1..n) mỗi khi người dùng chuyển bước.
  final void Function(int stepNumber)? onStepChanged;

  final _timers = <int, StepTimer>{};
  int _index;

  int get index => _index;
  int get stepNumber => _index + 1;
  int get total => steps.length;
  RecipeStep get current => steps[_index];
  bool get isFirst => _index == 0;
  bool get isLast => _index == steps.length - 1;

  /// 0..1 để vẽ thanh tiến độ
  double get progress => stepNumber / total;

  /// Bộ đếm giờ của bước [i] (null nếu bước không hẹn giờ). Tạo khi cần và giữ lại.
  StepTimer? timerFor(int i) {
    final seconds = steps[i].timerSeconds;
    if (seconds <= 0) return null;
    return _timers.putIfAbsent(i, () => StepTimer(Duration(seconds: seconds)));
  }

  StepTimer? get currentTimer => timerFor(_index);

  /// Mọi bộ đếm đang chạy (kể cả của bước khác), để báo khi hết giờ.
  Iterable<MapEntry<int, StepTimer>> get runningTimers =>
      _timers.entries.where((e) => e.value.isRunning);

  void next() {
    if (isLast) return;
    _index++;
    onStepChanged?.call(stepNumber);
    notifyListeners();
  }

  void previous() {
    if (isFirst) return;
    _index--;
    onStepChanged?.call(stepNumber);
    notifyListeners();
  }

  void startTimer() {
    currentTimer?.start(DateTime.now());
    notifyListeners();
  }

  void pauseTimer() {
    currentTimer?.pause(DateTime.now());
    notifyListeners();
  }

  void resetTimer() {
    currentTimer?.reset();
    notifyListeners();
  }

  /// Màn hình gọi mỗi giây để vẽ lại thời gian còn lại.
  void tick() => notifyListeners();
}
