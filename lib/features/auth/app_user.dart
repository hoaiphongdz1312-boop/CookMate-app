/// `user` trong hợp đồng API: {id, email, fullName, hasFace, role, tastes}
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.hasFace,
    this.role = 'User',
    this.tastes,
  });

  final int id;
  final String email;
  final String fullName;
  final bool hasFace;

  /// "User" hoặc "Admin"
  final String role;

  /// Nhãn khẩu vị đã chọn. null = chưa được hỏi, rỗng = đã bỏ qua.
  final List<String>? tastes;

  bool get needsTastes => tastes == null;

  bool get isAdmin => role == 'Admin';

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as int,
        email: json['email'] as String,
        fullName: json['fullName'] as String,
        hasFace: json['hasFace'] as bool? ?? false,
        role: json['role'] as String? ?? 'User',
        tastes: (json['tastes'] as List<dynamic>?)?.cast<String>(),
      );
}
