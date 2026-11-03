import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../../core/widgets.dart';
import 'resend_button.dart';

/// Nhập mã 6 số gửi về email sau khi đăng ký. Đúng mã thì vào app.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});
  final String email;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _code = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_code.text.length != 6) {
      setState(() => _error = 'Vui lòng nhập đủ 6 chữ số');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      await Services.of(context).auth.verifyEmail(widget.email, _code.text);
      // Thành công: go_router tự chuyển sang màn chính
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
      await Services.of(context).auth.resendCode(widget.email);
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
        title: const Text('Xác thực email'),
        leading: BackButton(onPressed: () => context.go('/login')),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.mark_email_read_outlined,
                      size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('Nhập mã xác thực',
                      textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Chúng tôi đã gửi mã 6 số tới\n${widget.email}\nMã có hiệu lực 10 phút.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _code,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 8),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(hintText: '000000', counterText: ''),
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
                        : const Text('Xác nhận'),
                  ),
                  const SizedBox(height: 8),
                  // Server vừa gửi mã lúc đăng ký/đăng nhập nên chờ 60 giây mới cho gửi lại
                  ResendCodeButton(onResend: _resend),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
