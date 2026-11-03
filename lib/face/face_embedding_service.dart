import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'face_config.dart';
import 'image_utils.dart';
import 'face_math.dart';

/// Sinh vector đặc trưng khuôn mặt bằng MobileFaceNet (TFLite).
///
/// Kích thước input/output được đọc từ model lúc chạy, không hardcode.
/// Inference chạy trên isolate riêng ([IsolateInterpreter]) để không chặn UI.
class FaceEmbeddingService {
  FaceEmbeddingService._(
    this._interpreter,
    this._isolate, {
    required this.inputWidth,
    required this.inputHeight,
    required this.embeddingSize,
  });

  final Interpreter _interpreter;
  final IsolateInterpreter _isolate;

  /// Kích thước ảnh mặt model cần (đọc từ tensor input dạng [1, H, W, 3]).
  final int inputWidth;
  final int inputHeight;

  /// Số chiều của vector đặc trưng (đọc từ tensor output).
  final int embeddingSize;

  static Future<FaceEmbeddingService>? _instance;

  /// Model chỉ nạp một lần và dùng chung cho cả app.
  /// Nếu nạp lỗi thì lần gọi sau sẽ thử lại.
  static Future<FaceEmbeddingService> instance() {
    final existing = _instance;
    if (existing != null) return existing;
    final future = load();
    _instance = future;
    future.then((_) {}, onError: (Object _) => _instance = null);
    return future;
  }

  static Future<FaceEmbeddingService> load() async {
    final interpreter = await Interpreter.fromAsset(
      FaceConfig.faceModelAsset,
      options: InterpreterOptions()..threads = 2,
    );
    final input = interpreter.getInputTensor(0);
    final output = interpreter.getOutputTensor(0);
    debugPrint('[FaceEmbedding] input: shape=${input.shape} type=${input.type}');
    debugPrint('[FaceEmbedding] output: shape=${output.shape} type=${output.type}');

    final inShape = input.shape;
    if (inShape.length != 4 || inShape[0] != 1 || inShape[3] != 3) {
      interpreter.close();
      throw UnsupportedError('Model cần input [1, H, W, 3], nhận được $inShape');
    }
    if (input.type != TensorType.float32 || output.type != TensorType.float32) {
      interpreter.close();
      throw UnsupportedError('Model cần input/output float32');
    }

    final isolate = await IsolateInterpreter.create(address: interpreter.address);
    return FaceEmbeddingService._(
      interpreter,
      isolate,
      inputHeight: inShape[1],
      inputWidth: inShape[2],
      embeddingSize: output.numElements(),
    );
  }

  /// Cắt mặt [face] từ frame camera và trả về vector đã chuẩn hóa L2.
  Future<Float32List> embedFace(
    CameraImage image,
    InputImageRotation rotation,
    Rect face,
  ) async {
    final sw = Stopwatch()..start();
    final upright = uprightSize(image.width, image.height, rotation);
    final crop = squareCropRect(
      face,
      upright,
      margin: FaceConfig.faceCropMargin,
      aspect: inputWidth / inputHeight,
    );
    final input = cropNv21ToModelInput(
      nv21: image.planes.first.bytes,
      width: image.width,
      height: image.height,
      rotation: rotation,
      crop: crop,
      outWidth: inputWidth,
      outHeight: inputHeight,
      mean: FaceConfig.modelInputMean,
      std: FaceConfig.modelInputStd,
    );
    final prepMs = sw.elapsedMilliseconds;

    final output = Float32List(embeddingSize);
    // Truyền ByteBuffer (không phải List) để tflite_flutter chép nguyên byte
    // vào tensor; nếu truyền List phẳng, thư viện sẽ tự resize tensor sai shape.
    await _isolate.run(input.buffer, output.buffer);
    debugPrint('[FaceEmbedding] crop+chuẩn hóa ${prepMs}ms, '
        'inference ${sw.elapsedMilliseconds - prepMs}ms');
    return l2Normalize(output);
  }

  Future<void> close() async {
    await _isolate.close();
    _interpreter.close();
  }
}
