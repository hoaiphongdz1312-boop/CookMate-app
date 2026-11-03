import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../../core/widgets.dart';

/// 6 nhãn khẩu vị, trùng với TasteTags.All ở server
const tasteTags = ['cay', 'chua', 'ngọt', 'đậm đà', 'thanh nhẹ', 'béo'];

/// Chọn khẩu vị. `editing` = mở từ Hồ sơ để sửa; ngược lại là lần hỏi đầu tiên sau khi đăng nhập.
class TastesScreen extends StatefulWidget {
  const TastesScreen({super.key, this.editing = false});

  final bool editing;

  @override
  State<TastesScreen> createState() => _TastesScreenState();
}

class _TastesScreenState extends State<TastesScreen> {
  late final Set<String> _selected;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = {...?Services.of(context).auth.user?.tastes};
  }

  Future<void> _save(List<String> tastes) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Services.of(context).auth.setTastes(tastes);
      if (!mounted) return;
      if (widget.editing) {
        context.pop();
      } else {
        context.go('/');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Khẩu vị của bạn'),
        automaticallyImplyLeading: widget.editing,
        actions: [
          if (!widget.editing)
            TextButton(
              onPressed: _saving ? null : () => _save(const []),
              child: const Text('Bỏ qua'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Bạn thích vị nào?', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Chọn nhiều vị tùy ý. CookMate sẽ gợi ý món hợp khẩu vị của bạn.',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final t in tasteTags)
                FilterChip(
                  label: Text(t),
                  selected: _selected.contains(t),
                  onSelected: _saving
                      ? null
                      : (on) => setState(() => on ? _selected.add(t) : _selected.remove(t)),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _saving ? null : () => _save(_selected.toList()),
            child: _saving
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Lưu'),
          ),
        ],
      ),
    );
  }
}
