import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../../core/widgets.dart';
import '../community/community_models.dart';
import '../recipes/recipe_image.dart';
import 'admin_repository.dart';
import 'admin_review_screens.dart' show ReasonDialog;

/// Báo cáo vi phạm chưa xử lý, gộp theo bài. Admin xem bài rồi Gỡ bài hoặc Bỏ qua.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  static const _takedownReasons = [
    'Nội dung phản cảm',
    'Quảng cáo hoặc spam',
    'Hướng dẫn nấu không an toàn',
    'Vi phạm bản quyền',
  ];

  late final AdminRepository _repo;
  List<ReportedRecipe> _items = [];
  bool _loading = true;
  String? _error;
  // Bài đang gọi API, khóa nút của bài đó
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _repo = AdminRepository(Services.of(context).api);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.reports(pageSize: 50);
      if (mounted) setState(() => _items = page.items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _takedown(ReportedRecipe item) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const ReasonDialog(
        reasons: _takedownReasons,
        title: 'Gỡ bài',
        confirmLabel: 'Gỡ bài',
      ),
    );
    if (reason == null) return;
    await _run(item, () => _repo.takedown(item.recipeId, reason), 'Đã gỡ bài');
  }

  Future<void> _dismiss(ReportedRecipe item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bỏ qua báo cáo?'),
        content: Text('Bài "${item.name}" vẫn hiển thị, ${item.reportCount} báo cáo sẽ được đóng.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Bỏ qua')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(item, () => _repo.dismissReports(item.recipeId), 'Đã bỏ qua báo cáo');
  }

  Future<void> _run(ReportedRecipe item, Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyId = item.recipeId);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      if (mounted) setState(() => _items.removeWhere((x) => x.recipeId == item.recipeId));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      // 404/409: admin khác đã xử lý, tải lại để thấy trạng thái mới
      if (e.statusCode == 404 || e.statusCode == 409) _load();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Báo cáo vi phạm')),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items.isEmpty
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 80),
                            EmptyView(icon: Icons.verified_user_outlined, message: 'Không có báo cáo nào cần xử lý'),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, i) => _card(_items[i]),
                        ),
                ),
    );
  }

  Widget _card(ReportedRecipe item) {
    final theme = Theme.of(context);
    final busy = _busyId == item.recipeId;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RecipeImage(size: 56, imageUrl: item.imageUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, style: theme.textTheme.titleMedium),
                      Text(item.authorName ?? 'Công thức hệ thống', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.flag, size: 18),
                  label: Text('${item.reportCount}'),
                  backgroundColor: theme.colorScheme.errorContainer,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final r in item.reports)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: r.reason.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (r.detail != null) TextSpan(text: ': ${r.detail}'),
                    TextSpan(
                      text: '  · ${r.reporterName}, ${timeAgo(r.createdAt)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ]),
                ),
              ),
            if (item.reportCount > item.reports.length)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('và ${item.reportCount - item.reports.length} báo cáo khác',
                    style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 12),
            // Theme cho nút rộng hết màn hình nên trong Row phải bọc Expanded (giống màn duyệt bài)
            Row(
              children: [
                IconButton.outlined(
                  tooltip: 'Xem bài',
                  onPressed: busy ? null : () => context.push('/recipes/${item.recipeId}'),
                  icon: const Icon(Icons.visibility_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : () => _dismiss(item),
                    child: const Text('Bỏ qua'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: busy ? null : () => _takedown(item),
                    child: const Text('Gỡ bài'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
