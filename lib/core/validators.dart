/// Validate phía app, khớp với luật của server (KE_HOACH_v2 mục 5, Auth).
class Validators {
  Validators._();

  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Vui lòng nhập email';
    if (!_emailRegex.hasMatch(v)) return 'Email không hợp lệ';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Vui lòng nhập mật khẩu';
    if (v.length < 8) return 'Mật khẩu phải có ít nhất 8 ký tự';
    return null;
  }

  static String? fullName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Vui lòng nhập họ tên';
    if (v.length > 100) return 'Họ tên quá dài';
    return null;
  }
}
