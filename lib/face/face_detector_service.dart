import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'face_config.dart';

/// Bọc ML Kit Face Detection.
///
/// Bật classification để có xác suất mở mắt (dùng cho chống ảnh giả) và
/// chế độ `fast` để chạy được trên luồng camera thời gian thực.
class FaceDetectorService {
  FaceDetectorService()
      : _detector = FaceDetector(
          options: FaceDetectorOptions(
            enableClassification: true,
            performanceMode: FaceDetectorMode.fast,
            minFaceSize: 0.15,
          ),
        );

  final FaceDetector _detector;

  Future<List<Face>> detect(InputImage image) => _detector.processImage(image);

  Future<void> close() => _detector.close();
}

/// Lý do một khuôn mặt chưa đủ chuẩn để lấy mẫu.
enum FaceQualityIssue { noFace, multipleFaces, tooSmall, notFrontal }

/// Kiểm tra khung hình có đúng 1 mặt, đủ lớn, nhìn thẳng hay không.
/// Trả về `null` nếu đạt.
FaceQualityIssue? checkFaceQuality(List<Face> faces, double imageWidth) {
  if (faces.isEmpty) return FaceQualityIssue.noFace;
  if (faces.length > 1) return FaceQualityIssue.multipleFaces;
  final face = faces.single;
  if (face.boundingBox.width < imageWidth * FaceConfig.minFaceWidthRatio) {
    return FaceQualityIssue.tooSmall;
  }
  final y = face.headEulerAngleY, z = face.headEulerAngleZ;
  if (y == null ||
      z == null ||
      y.abs() > FaceConfig.maxHeadEulerY ||
      z.abs() > FaceConfig.maxHeadEulerZ) {
    return FaceQualityIssue.notFrontal;
  }
  return null;
}

extension FaceQualityIssueText on FaceQualityIssue {
  String get message => switch (this) {
        FaceQualityIssue.noFace => 'Đưa khuôn mặt vào khung hình',
        FaceQualityIssue.multipleFaces => 'Chỉ để một người trong khung hình',
        FaceQualityIssue.tooSmall => 'Đưa mặt lại gần hơn',
        FaceQualityIssue.notFrontal => 'Nhìn thẳng vào camera',
      };
}
