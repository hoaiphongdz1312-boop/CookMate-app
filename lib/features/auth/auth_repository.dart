import '../../core/api_client.dart';
import 'app_user.dart';

class AuthResult {
  const AuthResult(this.token, this.user);
  final String token;
  final AppUser user;

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        json['token'] as String,
        AppUser.fromJson(json['user'] as Map<String, dynamic>),
      );
}

class AuthRepository {
  AuthRepository(this._api);
  final ApiClient _api;

  /// Server gửi mã 6 số về email, chưa trả token (phải xác thực email trước).
  Future<void> register({
    required String email,
    required String password,
    required String fullName,
  }) async {
    await _api.post<Map<String, dynamic>>('/auth/register', body: {
      'email': email,
      'password': password,
      'fullName': fullName,
    });
  }

  Future<AuthResult> verifyEmail({required String email, required String code}) async {
    final json = await _api.post<Map<String, dynamic>>('/auth/verify-email', body: {
      'email': email,
      'code': code,
    });
    return AuthResult.fromJson(json);
  }

  Future<void> resendCode(String email) =>
      _api.post<dynamic>('/auth/resend-code', body: {'email': email});

  Future<void> forgotPassword(String email) =>
      _api.post<dynamic>('/auth/forgot-password', body: {'email': email});

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) =>
      _api.post<dynamic>('/auth/reset-password', body: {
        'email': email,
        'code': code,
        'newPassword': newPassword,
      });

  Future<AuthResult> login({required String email, required String password}) async {
    final json = await _api.post<Map<String, dynamic>>('/auth/login', body: {
      'email': email,
      'password': password,
    });
    return AuthResult.fromJson(json);
  }

  Future<AuthResult> googleLogin(String idToken) async {
    final json = await _api.post<Map<String, dynamic>>('/auth/google', body: {
      'idToken': idToken,
    });
    return AuthResult.fromJson(json);
  }

  Future<AppUser> setTastes(List<String> tastes) async {
    final json = await _api.put<Map<String, dynamic>>('/users/me/tastes', body: {
      'tastes': tastes,
    });
    return AppUser.fromJson(json);
  }

  Future<AppUser> me() async {
    final json = await _api.get<Map<String, dynamic>>('/users/me');
    return AppUser.fromJson(json);
  }
}
