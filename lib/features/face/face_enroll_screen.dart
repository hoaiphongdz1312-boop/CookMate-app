import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../voice/voice_controller.dart';
import '../../core/widgets.dart';
import '../../face/camera_view.dart';
import '../../face/face_config.dart';
import '../../face/face_detector_service.dart';
import '../../face/face_embedding_service.dart';
import '../../face/face_math.dart';
import 'face_repository.dart';

/// Đăng ký khuôn mặt (đã đăng nhập): giải thích và xin đồng ý, tự chụp 3–5 mẫu,
/// gửi lên server. Chỉ gửi vector đặc trưng, không lưu ảnh.
class FaceEnrollScreen extends StatefulWidget {
  const FaceEnrollScreen({super.key});

  @override
  State<FaceEnrollScreen> createState() => _FaceEnrollScreenState();
}

class _FaceEnrollScreenState extends State<FaceEnrollScreen> {
  static const _initialHint = 'Đưa khuôn mặt vào khung hình';

  final _samples = <Float32List>[];
  FaceEmbeddingService? _embedder;
  String? _loadError;
  String? _submitError;
  String _hint = _initialHint;
  DateTime _lastSampleAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _consented = false;
  bool _submitting = false;
  bool _embedding = false;

  bool get _full => _samples.length >= FaceConfig.maxRegisterSamples;

  // Camera đang mở thì micro nghe "bếp ơi" nghỉ để không tranh chấp
  late final VoiceController _voice;

  @override
  void initState() {
    super.initState();
    _voice = Services.of(context).voice..hold(this);
    FaceEmbeddingService.instance().then(
      (e) => mounted ? setState(() => _embedder = e) : null,
      onError: (Object e) {
        debugPrint('[FaceEnroll] không nạp được model: $e');
        if (mounted) setState(() => _loadError = 'Không nạp được model nhận diện.');
      },
    );
  }

  Future<void> _onFrame(FaceFrame frame) async {
    final embedder = _embedder;
    if (embedder == null || _full || _submitting || _embedding) return;

    final issue = checkFaceQuality(frame.faces, frame.uprightSize.width);
    if (issue != null) {
      _setHint(issue.message);
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastSampleAt) < FaceConfig.registerSampleInterval) return;

    _embedding = true;
    try {
      final embedding = await embedder.embedFace(
        frame.image,
        frame.rotation,
        frame.faces.single.boundingBox,
      );
      if (!mounted) return;
      _lastSampleAt = DateTime.now();

      // Mọi mẫu phải của cùng một người: mẫu lệch hẳn so với các mẫu trước thì bỏ
      if (!isConsistentSample(
        embedding,
        _samples,
        minSimilarity: FaceConfig.registerSampleMinSimilarity,
      )) {
        _setHint('Chỉ một người đăng ký, giữ nguyên khuôn mặt trong khung');
        return;
      }
      setState(() {
        _samples.add(embedding);
        _hint = _full ? 'Đã chụp đủ ảnh' : 'Giữ yên, hơi đổi góc mặt một chút';
      });
    } finally {
      _embedding = false;
    }
  }

  void _setHint(String hint) {
    if (mounted && hint != _hint) setState(() => _hint = hint);
  }

  void _retake() => setState(() {
        _samples.clear();
        _submitError = null;
        _hint = _initialHint;
      });

  Future<void> _submit() async {
    final services = Services.of(context);
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await FaceRepository(services.api)
          .enroll([for (final s in _samples) s.toList()]);
      await services.auth.refreshUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã đăng ký khuôn mặt')));
      context.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      // 400 (mẫu không đồng nhất) và 409 (mặt đã thuộc tài khoản khác): cho chụp lại
      setState(() {
        _submitting = false;
        _samples.clear();
        _hint = _initialHint;
        _submitError = switch (e.statusCode) {
          409 => 'Khuôn mặt này đã được đăng ký cho một tài khoản khác.',
          400 => 'Các ảnh chụp chưa đồng nhất. Hãy chụp lại, chỉ một người trong khung.',
          _ => e.message,
        };
      });
    }
  }

  @override
  void dispose() {
    _voice.release(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng ký khuôn mặt')),
      body: SafeArea(child: _consented ? _buildCapture() : _buildConsent()),
    );
  }

  Widget _buildConsent() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.face_retouching_natural, size: 72, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text('Đăng nhập bằng khuôn mặt', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        const Text(
          '• App chụp vài khung hình khuôn mặt của bạn để tạo vector đặc trưng.\n'
          '• Chỉ vector đặc trưng được gửi lên máy chủ, ảnh KHÔNG được lưu.\n'
          '• Bạn có thể xóa dữ liệu khuôn mặt bất kỳ lúc nào trong Hồ sơ.\n'
          '• Luôn có thể đăng nhập bằng mật khẩu.',
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => setState(() => _consented = true),
          child: const Text('Tôi đồng ý, tiếp tục'),
        ),
      ],
    );
  }

  Widget _buildCapture() {
    final theme = Theme.of(context);
    final enough = _samples.length >= FaceConfig.minRegisterSamples;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (_submitError != null) ...[
            ErrorBanner(message: _submitError!),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: _loadError != null
                ? Center(child: Text(_loadError!))
                : FaceCameraView(
                    onFrame: _onFrame,
                    faceColor: _full ? Colors.green : null,
                  ),
          ),
          const SizedBox(height: 12),
          Text(_hint, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _samples.length / FaceConfig.maxRegisterSamples,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 4),
          Text(
            'Đã chụp ${_samples.length}/${FaceConfig.maxRegisterSamples} ảnh '
            '(tối thiểu ${FaceConfig.minRegisterSamples})',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _samples.isEmpty || _submitting ? null : _retake,
                  child: const Text('Chụp lại'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: enough && !_submitting ? _submit : null,
                  child: _submitting
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Lưu'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
