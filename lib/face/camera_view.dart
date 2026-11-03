import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import 'image_utils.dart';
import 'face_detector_service.dart';
import 'face_overlay.dart';

/// Một khung hình đã chạy qua ML Kit.
class FaceFrame {
  const FaceFrame({
    required this.image,
    required this.rotation,
    required this.faces,
    required this.uprightSize,
  });

  final CameraImage image;
  final InputImageRotation rotation;
  final List<Face> faces;

  /// Kích thước ảnh sau khi xoay đứng (hệ tọa độ của `Face.boundingBox`).
  final Size uprightSize;
}

/// Preview camera trước + phát hiện mặt + vẽ khung mặt.
///
/// Mỗi frame phát hiện xong được đưa cho [onFrame]. Trong lúc frame trước còn
/// đang xử lý (ML Kit hoặc [onFrame] chưa xong) thì các frame mới bị BỎ QUA,
/// nên không bị dồn hàng đợi và UI không giật.
class FaceCameraView extends StatefulWidget {
  const FaceCameraView({super.key, required this.onFrame, this.faceColor});

  final Future<void> Function(FaceFrame frame) onFrame;

  /// Màu khung mặt; mặc định là màu primary.
  final Color? faceColor;

  @override
  State<FaceCameraView> createState() => _FaceCameraViewState();
}

enum _Status { starting, ready, permissionDenied, noCamera, error }

class _FaceCameraViewState extends State<FaceCameraView>
    with WidgetsBindingObserver {
  final _detector = FaceDetectorService();
  CameraController? _controller;
  _Status _status = _Status.starting;
  bool _busy = false;
  bool _disposed = false;
  bool _pausedByLifecycle = false;
  bool _loggedFirstFrame = false;

  List<Rect> _faces = const [];
  Size _imageSize = const Size(1, 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    setState(() => _status = _Status.starting);

    final permission = await Permission.camera.request();
    if (!mounted) return;
    if (!permission.isGranted) {
      setState(() => _status = _Status.permissionDenied);
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _status = _Status.noCamera);
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        // ML Kit trên Android chỉ nhận NV21 (xem image_utils.dart).
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await controller.initialize();
      if (!mounted || _disposed) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      await controller.startImageStream(_onImage);
      setState(() => _status = _Status.ready);
    } on CameraException catch (e) {
      debugPrint('[Camera] ${e.code}: ${e.description}');
      if (!mounted) return;
      setState(() => _status = e.code == 'CameraAccessDenied'
          ? _Status.permissionDenied
          : _Status.error);
    }
  }

  void _onImage(CameraImage image) {
    // Bỏ frame nếu frame trước chưa xử lý xong.
    if (_busy || _disposed) return;
    _busy = true;
    _process(image).whenComplete(() => _busy = false);
  }

  Future<void> _process(CameraImage image) async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final rotation = rotationForCamera(
        controller.description,
        controller.value.deviceOrientation,
      );
      if (rotation == null) return;
      if (!_loggedFirstFrame) {
        _loggedFirstFrame = true;
        debugPrint('[Camera] frame ${image.width}x${image.height} '
            'format=${image.format.group} planes=${image.planes.length} '
            'sensor=${controller.description.sensorOrientation}° '
            'rotation=${rotation.rawValue}° '
            'preview=${controller.value.previewSize}');
      }
      final input = inputImageFromCameraImage(image, rotation);
      if (input == null) return;

      final faces = await _detector.detect(input);
      if (_disposed || !mounted) return;
      final size = uprightSize(image.width, image.height, rotation);
      setState(() {
        _faces = [for (final f in faces) f.boundingBox];
        _imageSize = size;
      });
      await widget.onFrame(FaceFrame(
        image: image,
        rotation: rotation,
        faces: faces,
        uprightSize: size,
      ));
    } catch (e, st) {
      debugPrint('[Camera] lỗi xử lý frame: $e\n$st');
    }
  }

  Future<void> _stop() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
    await controller.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Nhả camera khi app vào nền, mở lại khi quay về (kể cả khi người dùng
    // vừa cấp quyền trong Cài đặt hệ thống).
    // Lưu ý: hộp thoại xin quyền cũng làm app "inactive" → lúc đó _controller
    // còn null nên không bị ảnh hưởng.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_controller != null) {
        _pausedByLifecycle = true;
        _stop();
        setState(() => _status = _Status.starting);
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_pausedByLifecycle || _status == _Status.permissionDenied) {
        _pausedByLifecycle = false;
        _start();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    _detector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    return switch (_status) {
      _Status.starting => const Center(child: CircularProgressIndicator()),
      // Center cho CameraPreview ràng buộc "lỏng" để AspectRatio bên trong
      // tự chọn đúng tỉ lệ ảnh; nếu bị ép kích thước cố định thì khung vẽ sẽ
      // lệch khỏi hình camera thật.
      _Status.ready when controller != null => Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: CameraPreview(
              controller,
              child: CustomPaint(
                painter: FaceOverlayPainter(
                  faces: _faces,
                  imageSize: _imageSize,
                  mirror: controller.description.lensDirection ==
                      CameraLensDirection.front,
                  color: widget.faceColor ?? theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      _Status.permissionDenied => _Message(
          icon: Icons.no_photography_outlined,
          text: 'App cần quyền camera để nhận diện khuôn mặt.',
          actionLabel: 'Mở cài đặt',
          onAction: openAppSettings,
        ),
      _Status.noCamera => const _Message(
          icon: Icons.videocam_off_outlined,
          text: 'Không tìm thấy camera trên thiết bị.',
        ),
      _ => _Message(
          icon: Icons.error_outline,
          text: 'Không mở được camera.',
          actionLabel: 'Thử lại',
          onAction: _start,
        ),
    };
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
