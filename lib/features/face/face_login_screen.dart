import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../voice/voice_controller.dart';
import '../../face/camera_view.dart';
import '../../face/face_config.dart';
import '../../face/face_detector_service.dart';
import '../../face/face_embedding_service.dart';
import '../../face/liveness_service.dart';
import '../auth/auth_repository.dart';
import 'face_repository.dart';

enum _Phase { blink, capturing, submitting, greeting, failed }

/// Đăng nhập bằng khuôn mặt: mặt đạt chất lượng, chớp mắt 1 lần (chống ảnh in),
/// lấy 3 khung hình tạo 3 embedding rồi gửi 1 request tới server.
class FaceLoginScreen extends StatefulWidget {
  const FaceLoginScreen({super.key});

  @override
  State<FaceLoginScreen> createState() => _FaceLoginScreenState();
}

class _FaceLoginScreenState extends State<FaceLoginScreen> {
  static const _initialHint = 'Nhìn thẳng vào camera';
  static const _captureGap = Duration(milliseconds: 300);

  final _liveness = BlinkLivenessDetector();
  final _samples = <Float32List>[];
  FaceEmbeddingService? _embedder;
  String? _loadError;
  String? _networkError;
  _Phase _phase = _Phase.blink;
  String _hint = _initialHint;
  Duration _remaining = const Duration(seconds: 3);
  int _failedAttempts = 0;
  bool _embedding = false;
  DateTime _lastSampleAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _greetingName = '';

  // Camera đang mở thì micro nghe "bếp ơi" nghỉ để không tranh chấp
  late final VoiceController _voice;

  @override
  void initState() {
    super.initState();
    _voice = Services.of(context).voice..hold(this);
    FaceEmbeddingService.instance().then(
      (e) => mounted ? setState(() => _embedder = e) : null,
      onError: (Object e) {
        debugPrint('[FaceLogin] không nạp được model: $e');
        if (mounted) setState(() => _loadError = 'Không nạp được model nhận diện.');
      },
    );
  }

  Future<void> _onFrame(FaceFrame frame) async {
    final embedder = _embedder;
    if (embedder == null || _embedding) return;
    if (_phase != _Phase.blink && _phase != _Phase.capturing) return;

    final issue = checkFaceQuality(frame.faces, frame.uprightSize.width);
    if (issue != null) {
      // Mất mặt giữa chừng thì làm lại từ bước chớp mắt
      if (_phase == _Phase.capturing || _liveness.state != LivenessState.waiting) {
        _restartBlink();
      }
      _setHint(issue.message);
      return;
    }

    if (_phase == _Phase.blink) {
      final face = frame.faces.single;
      final now = DateTime.now();
      final state = _liveness.addFrame(
        face.leftEyeOpenProbability,
        face.rightEyeOpenProbability,
        now,
      );
      if (state == LivenessState.passed) {
        setState(() {
          _phase = _Phase.capturing;
          _hint = 'Giữ yên, đang quét...';
        });
      } else if (state == LivenessState.failed) {
        _restartBlink(hint: 'Chưa thấy chớp mắt, thử lại nhé');
      } else if (mounted) {
        setState(() {
          _remaining = _liveness.remaining(now);
          _hint = 'Chớp mắt một lần';
        });
      }
      return;
    }

    // Đang lấy mẫu
    if (DateTime.now().difference(_lastSampleAt) < _captureGap) return;
    _embedding = true;
    try {
      final embedding = await embedder.embedFace(
        frame.image,
        frame.rotation,
        frame.faces.single.boundingBox,
      );
      if (!mounted || _phase != _Phase.capturing) return;
      _lastSampleAt = DateTime.now();
      _samples.add(embedding);
      if (_samples.length >= FaceConfig.loginSamples) {
        await _submit();
      }
    } finally {
      _embedding = false;
    }
  }

  void _setHint(String hint) {
    if (mounted && hint != _hint) setState(() => _hint = hint);
  }

  void _restartBlink({String hint = _initialHint}) {
    _liveness.reset();
    _samples.clear();
    if (!mounted) return;
    setState(() {
      _phase = _Phase.blink;
      _hint = hint;
      _remaining = _liveness.window;
    });
  }

  Future<void> _submit() async {
    final services = Services.of(context);
    setState(() {
      _phase = _Phase.submitting;
      _hint = 'Đang xác thực...';
    });
    final embeddings = [for (final s in _samples) s.toList()];
    _samples.clear();
    try {
      final result = await FaceRepository(services.api).login(embeddings);
      if (!mounted) return;
      await _greetAndSignIn(result);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        _failedAttempts++;
        if (_failedAttempts >= FaceConfig.maxLoginAttempts) {
          setState(() => _phase = _Phase.failed);
        } else {
          _restartBlink(
            hint: 'Chưa nhận ra, thử lại ($_failedAttempts/${FaceConfig.maxLoginAttempts})',
          );
        }
      } else {
        // Lỗi mạng/server: không tính vào số lần thử
        setState(() => _networkError = e.message);
        _restartBlink(hint: e.message);
      }
    }
  }

  Future<void> _greetAndSignIn(AuthResult result) async {
    final auth = Services.of(context).auth;
    setState(() {
      _phase = _Phase.greeting;
      _greetingName = result.user.fullName;
    });
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    // Router tự chuyển về màn chính khi đã đăng nhập
    await auth.signInWith(result);
  }

  void _retryAll() {
    _failedAttempts = 0;
    _restartBlink();
  }

  @override
  void dispose() {
    _voice.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng nhập bằng khuôn mặt')),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.failed => _buildFailed(),
          _Phase.greeting => _buildGreeting(),
          _ => _buildScan(),
        },
      ),
    );
  }

  Widget _buildScan() {
    final theme = Theme.of(context);
    final seconds = (_remaining.inMilliseconds / 1000).ceil();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: _loadError != null
                ? Center(child: Text(_loadError!))
                : FaceCameraView(
                    onFrame: _onFrame,
                    faceColor: _phase == _Phase.capturing ? Colors.green : null,
                  ),
          ),
          const SizedBox(height: 12),
          Text(_hint,
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          if (_phase == _Phase.blink && _hint == 'Chớp mắt một lần')
            Text('Còn $seconds giây', style: theme.textTheme.bodyMedium),
          if (_phase == _Phase.submitting) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          if (_networkError != null) const SizedBox(height: 4),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text('Dùng mật khẩu'),
          ),
        ],
      ),
    );
  }

  Widget _buildGreeting() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 88, color: Colors.green),
          const SizedBox(height: 16),
          Text('Xin chào, $_greetingName!', style: theme.textTheme.titleLarge),
        ],
      ),
    );
  }

  Widget _buildFailed() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.face_retouching_off, size: 72, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Chưa nhận ra bạn', style: theme.textTheme.titleLarge),
            const SizedBox(height: 24),
            FilledButton(onPressed: _retryAll, child: const Text('Thử lại')),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go('/login'),
              child: const Text('Dùng mật khẩu'),
            ),
          ],
        ),
      ),
    );
  }
}
