import '../../core/api_client.dart';
import '../community/community_models.dart';

/// API duyệt bài của admin (/api/admin/recipes/*).
class AdminRepository {
  AdminRepository(this._api);
  final ApiClient _api;

  Future<Paged<PendingPost>> pending({int page = 1, int pageSize = 20}) async {
    final json = await _api.get<Map<String, dynamic>>('/admin/recipes/pending', query: {
      'page': page,
      'pageSize': pageSize,
    });
    return Paged.fromJson(json, PendingPost.fromJson);
  }

  Future<int> pendingCount() async {
    final json = await _api.get<Map<String, dynamic>>('/admin/recipes/pending/count');
    return json['count'] as int;
  }

  /// Thêm công thức hệ thống: duyệt sẵn, hiện ngay ở tab Công thức cho mọi người.
  Future<void> createRecipe(PostDraft draft) async {
    await _api.post<dynamic>('/admin/recipes', body: draft.toJson());
  }

  Future<void> approve(int id) async {
    await _api.post<dynamic>('/admin/recipes/$id/approve');
  }

  /// Admin xóa bài ở mọi trạng thái (xóa mềm).
  Future<void> delete(int id) async {
    await _api.delete<dynamic>('/community/recipes/$id');
  }

  Future<void> reject(int id, String reason) async {
    await _api.post<dynamic>('/admin/recipes/$id/reject', body: {'reason': reason});
  }

  /// Bài đang có báo cáo chưa xử lý, nhiều báo cáo nhất ở trên cùng.
  Future<Paged<ReportedRecipe>> reports({int page = 1, int pageSize = 20}) async {
    final json = await _api.get<Map<String, dynamic>>('/admin/reports', query: {
      'page': page,
      'pageSize': pageSize,
    });
    return Paged.fromJson(json, ReportedRecipe.fromJson);
  }

  /// Số bài đang có báo cáo chưa xử lý.
  Future<int> reportCount() async {
    final json = await _api.get<Map<String, dynamic>>('/admin/reports/count');
    return json['count'] as int;
  }

  /// Gỡ bài đang hiển thị (chuyển về Bị từ chối kèm lý do), đóng mọi báo cáo của bài.
  Future<void> takedown(int recipeId, String reason) async {
    await _api.post<dynamic>('/admin/reports/recipes/$recipeId/takedown', body: {'reason': reason});
  }

  /// Bỏ qua các báo cáo của bài, bài giữ nguyên.
  Future<void> dismissReports(int recipeId) async {
    await _api.post<dynamic>('/admin/reports/recipes/$recipeId/dismiss');
  }
}
