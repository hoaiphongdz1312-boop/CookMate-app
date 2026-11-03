import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart' show GoogleSignInException;

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../../core/validators.dart';
import '../../core/widgets.dart';
import 'auth_repository.dart';
import 'google_auth.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final email = _email.text.trim();
    final auth = Services.of(context).auth;
    try {
      await auth.login(email, _password.text);
      // Đăng nhập xong go_router tự chuyển sang màn chính
    } on ApiException catch (e) {
      if (e.statusCode == 403) {
        // Mật khẩu đúng nhưng email chưa xác thực: gửi mã mới rồi sang màn nhập mã
        try {
          await auth.resendCode(email);
        } on ApiException catch (_) {}
        if (mounted) context.go(Uri(path: '/verify-email', queryParameters: {'email': email}).toString());
        return;
      }
      setState(() => _error =
          e.statusCode == 401 ? 'Email hoặc mật khẩu không đúng' : e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final services = Services.of(context);
    try {
      final idToken = await GoogleAuth.signInForIdToken();
      if (idToken == null) return; // Người dùng hủy chọn tài khoản: im lặng
      final result = await AuthRepository(services.api).googleLogin(idToken);
      await services.auth.signInWith(result);
      // Đăng nhập xong go_router tự chuyển sang màn chính
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on GoogleSignInException catch (e) {
      if (mounted) {
        setState(() => _error = 'Đăng nhập Google thất bại'
            '${e.description == null ? '' : ': ${e.description}'}');
      }
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.restaurant_menu,
                          size: 64, color: theme.colorScheme.primary),
                      const SizedBox(height: 12),
                      Text('CookMate',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineLarge),
                      const SizedBox(height: 8),
                      Text('Đăng nhập để tiếp tục',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: Validators.email,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Mật khẩu',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                            icon: Icon(_obscure
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: Validators.password,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _loading ? null : () => context.go('/forgot-password'),
                          child: const Text('Quên mật khẩu?'),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        ErrorBanner(message: _error!),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(strokeWidth: 3))
                            : const Text('Đăng nhập'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.face_retouching_natural),
                        label: const Text('Đăng nhập bằng khuôn mặt'),
                        onPressed: _loading ? null : () => context.go('/face-login'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.g_mobiledata, size: 32),
                        label: const Text('Đăng nhập bằng Google'),
                        onPressed: _loading ? null : _googleSignIn,
                      ),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed:
                            _loading ? null : () => context.go('/register'),
                        child: const Text('Chưa có tài khoản? Đăng ký'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
