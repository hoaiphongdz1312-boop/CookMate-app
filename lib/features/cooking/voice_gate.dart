import 'voice_command_parser.dart';

enum VoiceGateState { idle, armed, cooldown }

/// Cổng 2 bước: nghe "bếp ơi" rồi mới nhận lệnh trong cửa sổ [armedWindow].
/// Thuần Dart: thời gian lấy qua [now] để unit test, hết hạn cửa sổ được xét
/// mỗi lần [feed] hoặc khi màn hình gọi [tick].
class VoiceGate {
  VoiceGate({
    required this.onCommand,
    this.onArmed,
    this.onDisarmed,
    DateTime Function()? now,
    this.armedWindow = const Duration(seconds: 5),
    this.cooldown = const Duration(milliseconds: 1500),
  }) : _now = now ?? DateTime.now;

  final void Function(VoiceCommand command) onCommand;
  final void Function()? onArmed;
  final void Function()? onDisarmed;
  final DateTime Function() _now;
  final Duration armedWindow;
  final Duration cooldown;

  VoiceGateState _state = VoiceGateState.idle;
  DateTime _since = DateTime.fromMillisecondsSinceEpoch(0);
  bool _paused = false;

  /// Câu partial đã thực thi lệnh; final cùng câu đó sau đó bị bỏ qua.
  String? _handledPartial;

  VoiceGateState get state => _state;

  /// Xét hết hạn cửa sổ armed / cooldown.
  void tick() {
    final elapsed = _now().difference(_since);
    if (_state == VoiceGateState.armed && elapsed >= armedWindow) {
      _state = VoiceGateState.idle;
      onDisarmed?.call();
    } else if (_state == VoiceGateState.cooldown && elapsed >= cooldown) {
      _state = VoiceGateState.idle;
    }
  }

  /// Nhận kết quả từ bộ nhận dạng. Lệnh chỉ thực thi từ final, trừ khi
  /// partial đã khớp đủ lệnh (khi đó final trùng câu sẽ bị bỏ qua).
  void feed(String text, {required bool isFinal}) {
    if (_paused) return;
    tick();

    final normalized = normalizeVoiceText(text);
    if (isFinal && _handledPartial != null) {
      final handled = _handledPartial;
      _handledPartial = null;
      if (handled == normalized) return;
    }
    if (normalized.isEmpty || normalized == '[unk]') return;
    if (_state == VoiceGateState.cooldown) return;

    final wake = containsWakeWord(normalized);
    final command = findVoiceCommand(normalized);

    if (_state == VoiceGateState.idle) {
      if (wake && command != null) {
        _execute(command, normalized, isFinal);
      } else if (wake) {
        _state = VoiceGateState.armed;
        _since = _now();
        onArmed?.call();
      }
      return;
    }

    // armed: cần lệnh hợp lệ, câu khác bỏ qua cho đến khi hết cửa sổ.
    if (command != null) {
      _state = VoiceGateState.idle;
      onDisarmed?.call();
      _execute(command, normalized, isFinal);
    }
  }

  void _execute(VoiceCommand command, String normalized, bool isFinal) {
    _state = VoiceGateState.cooldown;
    _since = _now();
    _handledPartial = isFinal ? null : normalized;
    onCommand(command);
  }

  /// Tạm bỏ qua mọi kết quả (app xuống nền, đang phát âm báo).
  void pause() {
    _paused = true;
    _handledPartial = null;
    final wasArmed = _state == VoiceGateState.armed;
    _state = VoiceGateState.idle;
    if (wasArmed) onDisarmed?.call();
  }

  void resume() => _paused = false;
}
