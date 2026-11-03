import 'package:flutter/foundation.dart';

import '../../core/api_exception.dart';
import '../../core/token_storage.dart';
import 'app_user.dart';
import 'auth_repository.dart';
import 'google_auth.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

/// Trạng thái đăng nhập của app. go_router lắng nghe lớp này để điều hướng.
class AuthController extends ChangeNotifier {
  AuthController(this._tokenStorage);

  final TokenStorage _tokenStorage;
  late AuthRepository _repo;

  AuthStatus _status = AuthStatus.unknown;
  AppUser? _user;

  AuthStatus get status => _status;
  AppUser? get user => _user;

  // Gán sau vì AuthRepository cần ApiClient, mà ApiClient lại cần callback logout của lớp này
  void attach(AuthRepository repo) => _repo = repo;

  /// Gọi khi mở app: còn token thì vào thẳng màn chính.
  Future<void> restore() async {
    final token = await _tokenStorage.read();
    if (token == null || token.isEmpty) {
      _set(AuthStatus.unauthenticated, null);
      return;
    }
    _set(AuthStatus.authenticated, null);

    // Lấy thông tin người dùng ở nền. Lỗi mạng thì vẫn giữ đăng nhập;
    // token hết hạn (401) thì ApiClient tự gọi onUnauthorized.
    try {
      _user = await _repo.me();
      notifyListeners();
    } on ApiException catch (_) {}
  }

  Future<void> login(String email, String password) async {
    final result = await _repo.login(email: email, password: password);
    await _tokenStorage.write(result.token);
    _set(AuthStatus.authenticated, result.user);
  }

  /// Đăng ký xong chưa vào app: cần nhập mã gửi về email (verifyEmail).
  Future<void> register(String email, String password, String fullName) =>
      _repo.register(email: email, password: password, fullName: fullName);

  Future<void> verifyEmail(String email, String code) async {
    final result = await _repo.verifyEmail(email: email, code: code);
    await _tokenStorage.write(result.token);
    _set(AuthStatus.authenticated, result.user);
  }

  /// Đăng nhập bằng token đã có (đăng nhập bằng khuôn mặt trả token như đăng nhập thường).
  Future<void> signInWith(AuthResult result) async {
    await _tokenStorage.write(result.token);
    _set(AuthStatus.authenticated, result.user);
  }

  /// Tải lại thông tin người dùng (vd. sau khi đăng ký/xóa khuôn mặt để cập nhật hasFace).
  Future<void> refreshUser() async {
    try {
      _user = await _repo.me();
      notifyListeners();
    } on ApiException catch (_) {}
  }

  /// Lưu khẩu vị (rỗng = bỏ qua). Lỗi thì ném ApiException, trạng thái không đổi.
  Future<void> setTastes(List<String> tastes) async {
    _user = await _repo.setTastes(tastes);
    notifyListeners();
  }

  Future<void> resendCode(String email) => _repo.resendCode(email);

  Future<void> forgotPassword(String email) => _repo.forgotPassword(email);

  Future<void> resetPassword(String email, String code, String newPassword) =>
      _repo.resetPassword(email: email, code: code, newPassword: newPassword);

  Future<void> logout() async {
    await _tokenStorage.clear();
    await GoogleAuth.signOut();
    _set(AuthStatus.unauthenticated, null);
  }

  /// ApiClient gọi khi server trả 401 cho request có token (token đã bị xóa trước đó).
  Future<void> onUnauthorized() async {
    if (_status != AuthStatus.unauthenticated) {
      _set(AuthStatus.unauthenticated, null);
    }
  }

  void _set(AuthStatus status, AppUser? user) {
    _status = status;
    _user = user;
    notifyListeners();
  }
}
