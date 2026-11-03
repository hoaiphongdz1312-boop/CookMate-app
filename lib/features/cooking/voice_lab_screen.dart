import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:vosk_flutter_service/vosk_flutter_service.dart';

import 'voice_service.dart';

/// Màn debug: nói vào máy và xem Vosk nhận ra chữ gì (partial và final).
/// Chỉ dùng để đo go/no-go, không nằm trong giao diện người dùng.
class VoiceLabScreen extends StatefulWidget {
  const VoiceLabScreen({super.key});

  @override
  State<VoiceLabScreen> createState() => _VoiceLabScreenState();
}

class _LabEntry {
  _LabEntry(this.time, this.isFinal, this.text);
  final DateTime time;
  final bool isFinal;
  final String text;
}

class _VoiceLabScreenState extends State<VoiceLabScreen> {
  static const _modelAsset = 'assets/models/vosk-model-small-vn-0.4.zip';
  static const _sampleRate = 16000;
  static const _grammar = VoiceService.grammar;

  final _vosk = VoskFlutterPlugin.instance();
  final _entries = <_LabEntry>[];
  final _subs = <StreamSubscription<String>>[];

  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _service;
  bool _useGrammar = true;
  bool _listening = false;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadModel());
  }

  Future<void> _loadModel() async {
    try {
      final path = await ModelLoader().loadFromAssets(_modelAsset);
      _model = await _vosk.createModel(path);
      await _buildService();
    } on Object catch (e) {
      _error = e is MicrophoneAccessDeniedException
          ? 'Chưa cấp quyền micro'
          : e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Tạo lại recognizer + speech service (đổi grammar thì phải tạo lại).
  Future<void> _buildService() async {
    await _releaseService();
    _recognizer = await _vosk.createRecognizer(
      model: _model!,
      sampleRate: _sampleRate,
      grammar: _useGrammar ? _grammar : null,
    );
    final service = await _vosk.initSpeechService(_recognizer!);
    _service = service;
    _subs
      ..add(service.onPartial().listen((s) => _onVosk(s, isFinal: false)))
      ..add(service.onResult().listen((s) => _onVosk(s, isFinal: true)));
  }

  Future<void> _releaseService() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _service?.dispose();
    await _recognizer?.dispose();
    _service = null;
    _recognizer = null;
  }

  void _onVosk(String json, {required bool isFinal}) {
    String text;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      text = (isFinal ? map['text'] : map['partial'])?.toString() ?? '';
    } on FormatException {
      text = json;
    }
    if (text.trim().isEmpty || !mounted) return;
    setState(() => _entries.insert(0, _LabEntry(DateTime.now(), isFinal, text)));
  }

  Future<void> _toggleListening() async {
    final service = _service;
    if (service == null) return;
    try {
      if (_listening) {
        await service.stop();
      } else {
        await service.start(
          onRecognitionError: (Object e) => setState(() => _error = '$e'),
        );
      }
      setState(() => _listening = !_listening);
    } on Object catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _setGrammar(bool value) async {
    setState(() {
      _useGrammar = value;
      _busy = true;
      _listening = false;
    });
    try {
      await _buildService();
      _error = null;
    } on Object catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    unawaited(_releaseService());
    super.dispose();
  }

  String _hms(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final ready = !_busy && _service != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thử giọng nói'),
        actions: [
          IconButton(
            tooltip: 'Xóa danh sách',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(_entries.clear),
          ),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text('Dùng grammar'),
            subtitle: const Text('Tắt để nhận dạng tự do'),
            value: _useGrammar,
            onChanged: _busy ? null : _setGrammar,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton.icon(
              onPressed: ready ? _toggleListening : null,
              icon: Icon(_listening ? Icons.stop : Icons.mic),
              label: Text(_busy
                  ? 'Đang tải model...'
                  : _listening
                      ? 'Dừng nghe'
                      : 'Bắt đầu nghe'),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (_, i) {
                final e = _entries[i];
                return ListTile(
                  dense: true,
                  leading: Icon(e.isFinal ? Icons.check_circle : Icons.more_horiz),
                  title: Text(e.text),
                  subtitle: Text('${_hms(e.time)} · ${e.isFinal ? 'final' : 'partial'}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
