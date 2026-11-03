import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../cooking/voice_command_parser.dart';
import '../cooking/voice_gate.dart';
import '../cooking/voice_service.dart';

/// Nghe "bếp ơi" ở cấp app: một micro, một cổng lệnh dùng chung cho mọi màn hình.
/// Lệnh nấu ăn đi tới [commandHandler] (màn nấu đăng ký), lệnh điều hướng đi tới [navigationHandler]; màn dùng camera gọi [hold]/[release]
/// để micro không tranh chấp. Xuống nền thì tự dừng nghe, quay lại thì nghe tiếp.
class VoiceController extends ChangeNotifier with WidgetsBindingObserver {
  VoiceController({VoiceEngine Function(VoiceResultCallback onResult)? engineFactory})
      : _engineFactory = engineFactory ?? ((onResult) => VoiceService(onResult: onResult)) {
    _gate = VoiceGate(
      onCommand: _dispatch,
      onArmed: () {
        HapticFeedback.mediumImpact();
        _setArmed(true);
      },
      onDisarmed: () => _setArmed(false),
    );
  }

  final VoiceEngine Function(VoiceResultCallback onResult) _engineFactory;
  late final VoiceGate _gate;
  VoiceEngine? _engine;
  Timer? _ticker;

  bool _enabled = false;
  bool _inBackground = false;
  bool _armed = false;
  final _holds = <Object>{};

  /// Nơi nhận lệnh nấu ăn đã qua cổng "bếp ơi": màn nấu đang mở. Chỉ một màn đăng ký tại một thời điểm.
  void Function(VoiceCommand command)? commandHandler;

  /// Nơi nhận lệnh điều hướng (mở món đang nấu, về trang chủ, hôm nay ăn gì). Cấp app đăng ký.
  void Function(VoiceCommand command)? navigationHandler;

  String? _notice;
  Timer? _noticeTimer;

  /// Câu báo ngắn trên bảng "Bạn cần gì?" (vd. lệnh không dùng được ở màn này)
  String? get notice => _notice;

  /// Bảng "Bạn cần gì?" đang hiện: vừa nghe "bếp ơi" hoặc đang có câu báo
  bool get panelVisible => _armed || _notice != null;

  /// Người dùng đã bật công tắc nghe "bếp ơi"
  bool get enabled => _enabled;

  /// Vừa nghe "bếp ơi", đang chờ lệnh
  bool get armed => _armed;

  VoiceStatus get status => _engine?.status.value ?? VoiceStatus.off;
  String? get error => _engine?.error;

  /// Có nên đang mở micro không: bật công tắc, app ở trước, không màn nào giữ micro
  bool get _shouldListen => _enabled && !_inBackground && _holds.isEmpty;

  Future<void> enable() async {
    if (_enabled) return;
    _enabled = true;
    WidgetsBinding.instance.addObserver(this);
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _gate.tick());
    notifyListeners();
    await _sync();
  }

  Future<void> disable() async {
    if (!_enabled) return;
    _enabled = false;
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _ticker = null;
    notifyListeners();
    await _sync();
  }

  Future<void> toggle() => _enabled ? disable() : enable();

  void _dispatch(VoiceCommand command) {
    if (!command.cooking) {
      navigationHandler?.call(command);
      return;
    }
    final handler = commandHandler;
    if (handler != null) {
      handler(command);
    } else if (command == VoiceCommand.next && navigationHandler != null) {
      // Ngoài màn nấu: cấp app mở món đang nấu dở rồi sang bước kế tiếp
      navigationHandler!(command);
    } else {
      showNotice('Hãy mở một món để dùng lệnh này');
    }
  }

  void showNotice(String message, {Duration duration = const Duration(seconds: 3)}) {
    _noticeTimer?.cancel();
    _notice = message;
    _noticeTimer = Timer(duration, () {
      _notice = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Đóng bảng "Bạn cần gì?" ngay (người dùng chạm vào bảng)
  void dismissPanel() {
    _noticeTimer?.cancel();
    _notice = null;
    if (_armed) {
      _gate.pause(); // hủy cửa sổ chờ lệnh, gọi onDisarmed
      if (_shouldListen) _gate.resume();
    }
    notifyListeners();
  }

  /// Màn dùng camera/chọn ảnh giữ micro: dừng nghe tới khi [release]. [owner] thường là `this`.
  void hold(Object owner) {
    if (_holds.add(owner)) unawaited(_sync());
  }

  void release(Object owner) {
    if (_holds.remove(owner)) unawaited(_sync());
  }

  /// Bỏ qua micro một lúc khi app phát âm báo hết giờ, để Vosk không nghe nhầm.
  void muteFor(Duration duration) {
    if (status != VoiceStatus.listening) return;
    _gate.pause();
    unawaited(_engine?.setPaused(true));
    Future<void>.delayed(duration, () {
      if (status != VoiceStatus.listening || !_shouldListen) return;
      unawaited(_engine?.setPaused(false));
      _gate.resume();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _inBackground = true;
      unawaited(_sync());
    } else if (state == AppLifecycleState.resumed && _inBackground) {
      _inBackground = false;
      unawaited(_sync());
    }
  }

  // Đưa micro về đúng trạng thái mong muốn
  Future<void> _sync() async {
    if (_shouldListen) {
      final engine = _engine ??= _createEngine();
      if (engine.status.value == VoiceStatus.listening ||
          engine.status.value == VoiceStatus.starting) {
        return;
      }
      _gate.resume();
      await engine.start();
    } else {
      _gate.pause();
      await _engine?.stop();
    }
    notifyListeners();
  }

  VoiceEngine _createEngine() {
    final engine = _engineFactory((text, {required isFinal}) => _gate.feed(text, isFinal: isFinal));
    engine.status.addListener(_onEngineStatus);
    return engine;
  }

  void _onEngineStatus() {
    // Lỗi micro/model: tự tắt công tắc để giao diện không báo "đang nghe" sai
    if (_engine?.status.value == VoiceStatus.unavailable && _enabled) {
      _enabled = false;
      WidgetsBinding.instance.removeObserver(this);
      _ticker?.cancel();
      _ticker = null;
      _gate.pause();
    }
    notifyListeners();
  }

  void _setArmed(bool value) {
    if (_armed == value) return;
    _armed = value;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _noticeTimer?.cancel();
    final engine = _engine;
    engine?.status.removeListener(_onEngineStatus);
    unawaited(engine?.dispose());
    super.dispose();
  }
}
