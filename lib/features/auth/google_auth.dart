import 'package:google_sign_in/google_sign_in.dart';

import '../../core/app_config.dart';

/// Lấy idToken từ Google để gửi cho server. google_sign_in v7: phải initialize
/// (đúng một lần) trước khi authenticate/signOut.
class GoogleAuth {
  GoogleAuth._();

  static Future<void>? _init;

  static Future<void> _ensureInitialized() => _init ??= GoogleSignIn.instance
      .initialize(serverClientId: AppConfig.googleServerClientId)
      .catchError((Object e) {
    _init = null; // cho phép thử lại lần sau
    throw e;
  });

  /// Trả null nếu người dùng hủy chọn tài khoản.
  /// Ném [GoogleSignInException] (hoặc StateError khi thiếu cấu hình) nếu lỗi khác.
  static Future<String?> signInForIdToken() async {
    if (AppConfig.googleServerClientId.isEmpty) {
      throw StateError('Thiếu GOOGLE_SERVER_CLIENT_ID. Chạy app với '
          '--dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id> (xem docs/GOOGLE_LOGIN.md)');
    }
    await _ensureInitialized();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw StateError('Google không trả idToken. Kiểm tra GOOGLE_SERVER_CLIENT_ID '
            'phải là Web client ID (xem docs/GOOGLE_LOGIN.md)');
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  /// Không ném lỗi: đăng xuất app không được hỏng vì Google.
  static Future<void> signOut() async {
    if (AppConfig.googleServerClientId.isEmpty) return;
    try {
      await _ensureInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}
