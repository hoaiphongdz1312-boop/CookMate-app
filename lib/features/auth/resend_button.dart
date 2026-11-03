import 'dart:async';

import 'package:flutter/material.dart';

/// Nút "Gửi lại mã" có đếm ngược 60 giây (khớp với giới hạn của server).
class ResendCodeButton extends StatefulWidget {
  const ResendCodeButton({super.key, required this.onResend, this.initialCooldown = 60});

  /// Gọi khi bấm gửi lại. Ném lỗi thì không bắt đầu đếm ngược.
  final Future<void> Function() onResend;
  final int initialCooldown;

  @override
  State<ResendCodeButton> createState() => _ResendCodeButtonState();
}

class _ResendCodeButtonState extends State<ResendCodeButton> {
  static const _cooldown = 60;

  Timer? _timer;
  late int _remaining = widget.initialCooldown;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    if (_remaining > 0) _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    setState(() => _sending = true);
    try {
      await widget.onResend();
      if (!mounted) return;
      setState(() => _remaining = _cooldown);
      _startTimer();
    } catch (_) {
      // Màn hình cha tự hiện lỗi trong onResend
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _remaining > 0;
    return TextButton(
      onPressed: waiting || _sending ? null : _resend,
      child: Text(waiting ? 'Gửi lại mã sau ${_remaining}s' : 'Gửi lại mã'),
    );
  }
}
