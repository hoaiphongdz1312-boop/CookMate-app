// Model cho tính năng Cộng đồng (KE_HOACH_CHIA_SE_CONG_THUC mục 4).

/// Trạng thái bài chia sẻ, đúng giá trị cột Status ở server.
enum PostStatus {
  pending,
  approved,
  rejected;

  static PostStatus fromCode(int code) => switch (code) {
        0 => PostStatus.pending,
        1 => PostStatus.approved,
        2 => PostStatus.rejected,
        _ => throw FormatException('Trạng thái bài không hợp lệ: $code'),
      };

  String get label => switch (this) {
        PostStatus.pending => 'Chờ duyệt',
        PostStatus.approved => 'Đã duyệt',
        PostStatus.rejected => 'Bị từ chối',
      };
}

/// Một thẻ trong feed GET /api/community/recipes
class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.difficulty,
    required this.prepMinutes,
    required this.cookMinutes,
    required this.categoryId,
    required this.authorId,
    required this.authorName,
    required this.publishedAt,
  });

  final int id;
  final String name;
  final String description;
  final String? imageUrl;
  final int difficulty;
  final int prepMinutes;
  final int cookMinutes;
  final int categoryId;
  final int? authorId;
  final String? authorName;
  final DateTime? publishedAt;

  int get totalMinutes => prepMinutes + cookMinutes;

  factory CommunityPost.fromJson(Map<String, dynamic> json) => CommunityPost(
        id: json['id'] as int,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        difficulty: json['difficulty'] as int,
        prepMinutes: json['prepMinutes'] as int,
        cookMinutes: json['cookMinutes'] as int,
        categoryId: json['categoryId'] as int,
        authorId: json['authorId'] as int?,
        authorName: json['authorName'] as String?,
        publishedAt: _parseTime(json['publishedAt']),
      );
}

/// Một bài trong GET /api/community/recipes/mine
class MyPost {
  const MyPost({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.status,
    required this.rejectReason,
    required this.submittedAt,
  });

  final int id;
  final String name;
  final String description;
  final String? imageUrl;
  final PostStatus status;
  final String? rejectReason;
  final DateTime? submittedAt;

  factory MyPost.fromJson(Map<String, dynamic> json) => MyPost(
        id: json['id'] as int,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        status: PostStatus.fromCode(json['status'] as int),
        rejectReason: json['rejectReason'] as String?,
        submittedAt: _parseTime(json['submittedAt']),
      );
}

/// Một bài trong hàng đợi duyệt GET /api/admin/recipes/pending
class PendingPost {
  const PendingPost({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.authorName,
    required this.submittedAt,
  });

  final int id;
  final String name;
  final String? imageUrl;
  final String authorName;
  final DateTime submittedAt;

  factory PendingPost.fromJson(Map<String, dynamic> json) => PendingPost(
        id: json['id'] as int,
        name: json['name'] as String,
        imageUrl: json['imageUrl'] as String?,
        authorName: json['authorName'] as String? ?? '',
        submittedAt: _parseTime(json['submittedAt']) ?? DateTime.now(),
      );
}

class Paged<T> {
  const Paged({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final int total;

  bool get hasMore => page * pageSize < total;

  factory Paged.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) =>
      Paged(
        items: (json['items'] as List<dynamic>)
            .map((e) => parse(e as Map<String, dynamic>))
            .toList(),
        page: json['page'] as int,
        pageSize: json['pageSize'] as int,
        total: json['total'] as int,
      );
}

DateTime? _parseTime(Object? value) {
  if (value is! String) return null;
  // Server trả giờ UTC không kèm "Z" trong một số trường hợp; coi là UTC rồi đổi sang giờ máy
  final hasZone = value.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(value);
  return DateTime.tryParse(hasZone ? value : '${value}Z')?.toLocal();
}

/// "5 phút trước", "2 giờ trước", "3 ngày trước"
String timeAgo(DateTime? time, {DateTime? now}) {
  if (time == null) return '';
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inMinutes < 1) return 'vừa xong';
  if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
  if (diff.inHours < 24) return '${diff.inHours} giờ trước';
  if (diff.inDays < 30) return '${diff.inDays} ngày trước';
  return '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year}';
}

// ---------- Bản nháp trong form tạo/sửa bài ----------

class IngredientDraft {
  IngredientDraft({this.name = '', this.quantity = '', this.unit = '', this.isOptional = false});

  String name;
  String quantity;
  String unit;
  bool isOptional;

  double? get quantityValue => double.tryParse(quantity.trim().replaceAll(',', '.'));

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'quantity': quantityValue ?? 0,
        'unit': unit.trim(),
        'isOptional': isOptional,
      };
}

class StepDraft {
  StepDraft({this.instruction = '', this.timerMinutes = 0});

  String instruction;

  /// Phút; 0 = không hẹn giờ
  int timerMinutes;

  Map<String, dynamic> toJson() => {
        'instruction': instruction.trim(),
        'timerSeconds': timerMinutes * 60,
      };
}

/// Giới hạn nội dung, khớp PostValidator ở server.
class PostLimits {
  PostLimits._();
  static const maxName = 100;
  static const maxDescription = 1000;
  static const maxIngredients = 40;
  static const maxSteps = 30;
  static const maxStepText = 1000;
  static const maxTimerMinutes = 1440; // 86400 giây
  static const maxServings = 20;
}

class PostDraft {
  PostDraft({
    this.name = '',
    this.description = '',
    this.imageUrl,
    this.difficulty = 1,
    this.prepMinutes = 0,
    this.cookMinutes = 0,
    this.baseServings = 2,
    this.categoryId,
    List<IngredientDraft>? ingredients,
    List<StepDraft>? steps,
  })  : ingredients = ingredients ?? [IngredientDraft()],
        steps = steps ?? [StepDraft()];

  String name;
  String description;

  /// Đường dẫn ảnh server trả về sau khi upload (vd. /uploads/abc.jpg)
  String? imageUrl;
  int difficulty;
  int prepMinutes;
  int cookMinutes;
  int baseServings;
  int? categoryId;
  List<IngredientDraft> ingredients;
  List<StepDraft> steps;

  /// Lỗi đầu tiên của bản nháp, null nếu hợp lệ. Server vẫn kiểm tra lại.
  String? validate() {
    if (name.trim().isEmpty) return 'Vui lòng nhập tên món';
    if (name.trim().length > PostLimits.maxName) {
      return 'Tên món tối đa ${PostLimits.maxName} ký tự';
    }
    if (description.trim().isEmpty) return 'Vui lòng nhập mô tả';
    if (description.trim().length > PostLimits.maxDescription) {
      return 'Mô tả tối đa ${PostLimits.maxDescription} ký tự';
    }
    if (categoryId == null) return 'Vui lòng chọn danh mục';
    if (prepMinutes < 0 || cookMinutes < 0) return 'Thời gian không được âm';
    if (baseServings < 1 || baseServings > PostLimits.maxServings) {
      return 'Khẩu phần phải từ 1 đến ${PostLimits.maxServings}';
    }
    if (ingredients.isEmpty) return 'Cần ít nhất 1 nguyên liệu';
    if (ingredients.length > PostLimits.maxIngredients) {
      return 'Tối đa ${PostLimits.maxIngredients} nguyên liệu';
    }
    for (final i in ingredients) {
      if (i.name.trim().isEmpty) return 'Có nguyên liệu chưa nhập tên';
      final q = i.quantityValue;
      if (q == null) return 'Số lượng của "${i.name.trim()}" không hợp lệ';
      if (q < 0) return 'Số lượng không được âm';
      if (i.unit.trim().isEmpty) return 'Nguyên liệu "${i.name.trim()}" thiếu đơn vị';
    }
    if (steps.isEmpty) return 'Cần ít nhất 1 bước';
    if (steps.length > PostLimits.maxSteps) {
      return 'Tối đa ${PostLimits.maxSteps} bước';
    }
    for (final s in steps) {
      if (s.instruction.trim().isEmpty) return 'Có bước chưa nhập nội dung';
      if (s.instruction.trim().length > PostLimits.maxStepText) {
        return 'Mỗi bước tối đa ${PostLimits.maxStepText} ký tự';
      }
      if (s.timerMinutes < 0 || s.timerMinutes > PostLimits.maxTimerMinutes) {
        return 'Thời gian hẹn giờ phải từ 0 đến ${PostLimits.maxTimerMinutes} phút';
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'description': description.trim(),
        'imageUrl': imageUrl,
        'difficulty': difficulty,
        'prepMinutes': prepMinutes,
        'cookMinutes': cookMinutes,
        'baseServings': baseServings,
        'categoryId': categoryId,
        'ingredients': ingredients.map((e) => e.toJson()).toList(),
        'steps': steps.map((e) => e.toJson()).toList(),
      };
}

// ---------- Báo cáo, chặn, thông báo ----------

/// Lý do báo cáo vi phạm, [code] khớp ReportReasons ở server.
enum ReportReason {
  wrongInfo('wrong_info', 'Sai thông tin'),
  spam('spam', 'Spam, quảng cáo'),
  offensive('offensive', 'Nội dung xấu, phản cảm'),
  copyright('copyright', 'Vi phạm bản quyền'),
  other('other', 'Khác');

  const ReportReason(this.code, this.label);
  final String code;
  final String label;

  static ReportReason fromCode(String code) =>
      values.firstWhere((r) => r.code == code, orElse: () => ReportReason.other);
}

/// Một người trong GET /api/users/me/blocks
class BlockedUser {
  const BlockedUser({required this.id, required this.fullName, required this.blockedAt});

  final int id;
  final String fullName;
  final DateTime? blockedAt;

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
        id: json['id'] as int,
        fullName: json['fullName'] as String? ?? '',
        blockedAt: _parseTime(json['blockedAt']),
      );
}

class ReportItem {
  const ReportItem({
    required this.id,
    required this.reason,
    required this.detail,
    required this.reporterName,
    required this.createdAt,
  });

  final int id;
  final ReportReason reason;
  final String? detail;
  final String reporterName;
  final DateTime? createdAt;

  factory ReportItem.fromJson(Map<String, dynamic> json) => ReportItem(
        id: json['id'] as int,
        reason: ReportReason.fromCode(json['reason'] as String),
        detail: json['detail'] as String?,
        reporterName: json['reporterName'] as String? ?? '',
        createdAt: _parseTime(json['createdAt']),
      );
}

/// Một bài trong GET /api/admin/reports: các báo cáo chưa xử lý gộp theo bài
class ReportedRecipe {
  const ReportedRecipe({
    required this.recipeId,
    required this.name,
    required this.imageUrl,
    required this.authorName,
    required this.reportCount,
    required this.latestReportAt,
    required this.reports,
  });

  final int recipeId;
  final String name;
  final String? imageUrl;

  /// null với công thức hệ thống
  final String? authorName;
  final int reportCount;
  final DateTime? latestReportAt;
  final List<ReportItem> reports;

  factory ReportedRecipe.fromJson(Map<String, dynamic> json) => ReportedRecipe(
        recipeId: json['recipeId'] as int,
        name: json['name'] as String,
        imageUrl: json['imageUrl'] as String?,
        authorName: json['authorName'] as String?,
        reportCount: json['reportCount'] as int,
        latestReportAt: _parseTime(json['latestReportAt']),
        reports: (json['reports'] as List<dynamic>? ?? [])
            .map((e) => ReportItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Một thông báo trong GET /api/notifications
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.recipeId,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
  });

  final int id;

  /// post_approved, post_rejected hoặc post_removed
  final String type;
  final int? recipeId;
  final String title;
  final String body;
  final bool isRead;
  final DateTime? createdAt;

  bool get isPositive => type == 'post_approved';

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as int,
        type: json['type'] as String,
        recipeId: json['recipeId'] as int?,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        isRead: json['isRead'] as bool? ?? false,
        createdAt: _parseTime(json['createdAt']),
      );
}

/// Thông báo sau khi đăng bài, theo trạng thái server trả về.
String createdMessage(PostStatus status) => status == PostStatus.approved
    ? 'Đã đăng, bài đã hiện ở tab Cộng đồng'
    : 'Bài đang chờ duyệt, bạn sẽ nhận thông báo khi có kết quả';
