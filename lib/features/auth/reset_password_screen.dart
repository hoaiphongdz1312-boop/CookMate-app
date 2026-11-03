import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../../core/validators.dart';
import '../../core/widgets.dart';
import 'resend_button.dart';

/// Bước 2 quên mật khẩu: nhập mã nhận được và mật khẩu mới.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.email});
  final String email;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await Services.of(context).auth.resetPassword(widget.email, _code.text, _password.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã đổi mật khẩu. Hãy đăng nhập bằng mật khẩu mới.')),
      );
      context.go('/login');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      await Services.of(context).auth.forgotPassword(widget.email);
      if (mounted) setState(() => _info = 'Đã gửi lại mã. Kiểm tra hộp thư (cả mục Spam).');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đặt lại mật khẩu'),
        leading: BackButton(onPressed: () => context.go('/forgot-password')),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Nếu ${widget.email} đã đăng ký, một mã 6 số vừa được gửi tới. Mã có hiệu lực 10 phút.',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _code,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Mã 6 số',
                        prefixIcon: Icon(Icons.pin_outlined),
                        counterText: '',
                      ),
                      validator: (v) => (v?.length ?? 0) == 6 ? null : 'Vui lòng nhập đủ 6 chữ số',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu mới (ít nhất 8 ký tự)',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: Validators.password,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirm,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(
                        labelText: 'Nhập lại mật khẩu mới',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      validator: (v) => v != _password.text ? 'Mật khẩu nhập lại không khớp' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      ErrorBanner(message: _error!),
                    ],
                    if (_info != null) ...[
                      const SizedBox(height: 16),
                      Text(_info!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.primary)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox.square(
                              dimension: 24, child: CircularProgressIndicator(strokeWidth: 3))
                          : const Text('Đổi mật khẩu'),
                    ),
                    const SizedBox(height: 8),
                    ResendCodeButton(onResend: _resend),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
