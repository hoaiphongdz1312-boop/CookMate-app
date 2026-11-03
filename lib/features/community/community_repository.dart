import 'package:dio/dio.dart';

import '../../core/api_client.dart';
import 'community_models.dart';

/// API chia sẻ công thức (/api/community/*).
class CommunityRepository {
  CommunityRepository(this._api);
  final ApiClient _api;

  Future<Paged<CommunityPost>> feed({
    String? search,
    int? categoryId,
    int page = 1,
    int pageSize = 20,
  }) async {
    final json = await _api.get<Map<String, dynamic>>('/community/recipes', query: {
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      'categoryId': ?categoryId,
      'page': page,
      'pageSize': pageSize,
    });
    return Paged.fromJson(json, CommunityPost.fromJson);
  }

  Future<Paged<MyPost>> mine({PostStatus? status, int page = 1, int pageSize = 20}) async {
    final json = await _api.get<Map<String, dynamic>>('/community/recipes/mine', query: {
      'status': ?status?.index,
      'page': page,
      'pageSize': pageSize,
    });
    return Paged.fromJson(json, MyPost.fromJson);
  }

  /// Tạo bài. Tác giả mới: bài chờ duyệt; tác giả đã có đủ bài được duyệt: bài lên feed ngay.
  /// Xem [MyPost.status] của bài trả về.
  Future<MyPost> create(PostDraft draft) async {
    final json = await _api.post<Map<String, dynamic>>('/community/recipes', body: draft.toJson());
    return MyPost.fromJson(json);
  }

  /// Sửa bài chờ duyệt/bị từ chối; sau khi sửa bài quay về chờ duyệt.
  Future<MyPost> update(int id, PostDraft draft) async {
    final json =
        await _api.put<Map<String, dynamic>>('/community/recipes/$id', body: draft.toJson());
    return MyPost.fromJson(json);
  }

  Future<void> delete(int id) async {
    await _api.delete<dynamic>('/community/recipes/$id');
  }

  /// Báo cáo vi phạm. Server trả 409 nếu đã báo cáo bài này rồi.
  Future<void> report(int recipeId, ReportReason reason, {String? detail}) async {
    await _api.post<dynamic>('/community/recipes/$recipeId/report', body: {
      'reason': reason.code,
      if (detail != null && detail.trim().isNotEmpty) 'detail': detail.trim(),
    });
  }

  /// Chặn người dùng: bài của họ không còn hiện trong feed của mình.
  Future<void> block(int userId) async {
    await _api.post<dynamic>('/users/$userId/block');
  }

  Future<void> unblock(int userId) async {
    await _api.delete<dynamic>('/users/$userId/block');
  }

  Future<List<BlockedUser>> blockedUsers() async {
    final json = await _api.get<List<dynamic>>('/users/me/blocks');
    return json.map((e) => BlockedUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Paged<AppNotification>> notifications({int page = 1, int pageSize = 30}) async {
    final json = await _api.get<Map<String, dynamic>>('/notifications', query: {
      'page': page,
      'pageSize': pageSize,
    });
    return Paged.fromJson(json, AppNotification.fromJson);
  }

  Future<int> unreadNotificationCount() async {
    final json = await _api.get<Map<String, dynamic>>('/notifications/unread-count');
    return json['count'] as int;
  }

  Future<void> markAllNotificationsRead() async {
    await _api.post<dynamic>('/notifications/read-all');
  }

  /// Upload ảnh từ file trên máy, trả về đường dẫn ảnh trên server (vd. /uploads/abc.jpg).
  Future<String> uploadImage(String filePath) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: 'image'),
    });
    final json = await _api.post<Map<String, dynamic>>('/community/images', body: form);
    return json['imageUrl'] as String;
  }
}
