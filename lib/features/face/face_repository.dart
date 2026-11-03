import '../../core/api_client.dart';
import '../auth/auth_repository.dart';

/// Gọi API khuôn mặt (KE_HOACH_v2 mục 5). Chỉ gửi vector đặc trưng, không gửi ảnh.
class FaceRepository {
  FaceRepository(this._api);
  final ApiClient _api;

  /// 204; 400 mẫu không đồng nhất; 409 khuôn mặt thuộc tài khoản khác.
  Future<void> enroll(List<List<double>> embeddings) =>
      _api.post<dynamic>('/auth/face-enroll', body: {'embeddings': embeddings});

  /// 401 nếu không nhận ra; luôn gửi đúng 3 vector.
  Future<AuthResult> login(List<List<double>> embeddings) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/auth/face-login',
      body: {'embeddings': embeddings},
    );
    return AuthResult.fromJson(json);
  }

  Future<void> delete() => _api.delete<dynamic>('/auth/face');
}
