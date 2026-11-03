import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:vosk_flutter_service/vosk_flutter_service.dart';

enum VoiceStatus { off, starting, listening, unavailable }

/// Lấy chữ từ JSON của Vosk: {"text": ...} (final) hoặc {"partial": ...}.
String parseVoskText(String json, {required bool isFinal}) {
  try {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return (isFinal ? map['text'] : map['partial'])?.toString() ?? '';
  } on FormatException {
    return json;
  }
}

typedef VoiceResultCallback = void Function(String text, {required bool isFinal});

/// Phần VoiceController cần từ bộ nhận dạng (để test thay bằng bản giả).
abstract interface class VoiceEngine {
  ValueNotifier<VoiceStatus> get status;
  String? get error;
  Future<void> start();
  Future<void> stop();
  Future<void> setPaused(bool paused);
  Future<void> dispose();
}

/// Bọc Vosk: nghe micro và đưa chữ nhận được cho [onResult].
/// Model nạp một lần, recognizer + speech service tạo lại mỗi lần [start].
/// Mọi lỗi (quyền micro, model) chỉ chuyển [status] sang `unavailable`, không ném ra ngoài.
class VoiceService implements VoiceEngine {
  VoiceService({required this.onResult});

  static const modelAsset = 'assets/models/vosk-model-small-vn-0.4.zip';
  static const sampleRate = 16000;
  static const grammar = [
    'bếp ơi',
    'bước tiếp theo',
    'bước trước',
    'hẹn giờ',
    'dừng hẹn giờ',
    'mở món đang nấu',
    'về trang chủ',
    'hôm nay ăn gì',
    '[unk]',
  ];

  final VoiceResultCallback onResult;
  @override
  final status = ValueNotifier<VoiceStatus>(VoiceStatus.off);

  /// Thông báo gọn khi [status] là `unavailable`.
  @override
  String? error;

  final _vosk = VoskFlutterPlugin.instance();
  final _subs = <StreamSubscription<String>>[];
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _service;
  int _epoch = 0; // tăng mỗi lần start/stop để bỏ kết quả của lần start đã bị hủy

  @override
  Future<void> start() async {
    final epoch = ++_epoch;
    error = null;
    status.value = VoiceStatus.starting;
    try {
      await _release();
      if (_model == null) {
        final path = await ModelLoader().loadFromAssets(modelAsset);
        _model = await _vosk.createModel(path);
      }
      final recognizer = await _vosk.createRecognizer(
        model: _model!,
        sampleRate: sampleRate,
        grammar: grammar,
      );
      final service = await _vosk.initSpeechService(recognizer);
      if (epoch != _epoch) {
        await service.dispose();
        await recognizer.dispose();
        return;
      }
      _recognizer = recognizer;
      _service = service;
      _subs
        ..add(service.onPartial().listen(
            (s) => onResult(parseVoskText(s, isFinal: false), isFinal: false)))
        ..add(service.onResult().listen(
            (s) => onResult(parseVoskText(s, isFinal: true), isFinal: true)));
      await service.start(onRecognitionError: (Object e) => _fail('$e'));
      if (epoch != _epoch) return;
      status.value = VoiceStatus.listening;
    } on MicrophoneAccessDeniedException {
      if (epoch == _epoch) _fail('Chưa cấp quyền micro');
    } on Object catch (e) {
      if (epoch == _epoch) _fail('Không bật được giọng nói: $e');
    }
  }

  @override
  Future<void> stop() async {
    _epoch++;
    await _release();
    status.value = VoiceStatus.off;
  }

  /// Tạm dừng / nghe tiếp mà không tạo lại service (vd. lúc app phát âm báo).
  @override
  Future<void> setPaused(bool paused) async {
    try {
      await _service?.setPause(paused: paused);
    } on Object {
      // bỏ qua: gate cũng đang pause nên kết quả vẫn bị bỏ
    }
  }

  void _fail(String message) {
    error = message;
    status.value = VoiceStatus.unavailable;
  }

  Future<void> _release() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final service = _service;
    final recognizer = _recognizer;
    _service = null;
    _recognizer = null;
    // Phải stop() (chờ luồng thu âm kết thúc) trước dispose(): dispose() giải phóng micro ngay,
    // luồng thu âm còn đang đọc sẽ ném "error reading audio buffer" và làm văng app.
    try {
      await service?.stop();
    } on Object {
      // chưa start hoặc đã dừng
    }
    try {
      await service?.dispose();
      await recognizer?.dispose();
    } on Object {
      // đã hủy rồi
    }
  }

  @override
  Future<void> dispose() async {
    _epoch++;
    await _release();
    status.dispose();
  }
}
