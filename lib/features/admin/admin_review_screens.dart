import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../../core/widgets.dart';
import '../community/community_models.dart';
import '../recipes/recipe_detail_screen.dart' show formatDuration;
import '../recipes/recipe_image.dart';
import '../recipes/recipe_list_screen.dart' show InfoTag;
import '../recipes/recipe_models.dart';
import 'admin_repository.dart';

/// Hàng đợi bài chờ duyệt, bài gửi sớm nhất ở trên cùng.
class AdminReviewListScreen extends StatefulWidget {
  const AdminReviewListScreen({super.key});

  @override
  State<AdminReviewListScreen> createState() => _AdminReviewListScreenState();
}

class _AdminReviewListScreenState extends State<AdminReviewListScreen> {
  late final AdminRepository _repo;
  List<PendingPost> _posts = [];
  bool _loading = true;
  String? _error;

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
      final page = await _repo.pending(pageSize: 50);
      if (mounted) setState(() => _posts = page.items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(PendingPost post) async {
    await context.push<bool>('/admin/review/${post.id}');
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Duyệt công thức')),
      body: _loading && _posts.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _posts.isEmpty
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _posts.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 80),
                            EmptyView(
                              icon: Icons.task_alt,
                              message: 'Không có bài nào đang chờ duyệt',
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _posts.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, i) {
                            final p = _posts[i];
                            return Card(
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(12),
                                leading: RecipeImage(size: 56, imageUrl: p.imageUrl),
                                title: Text(p.name),
                                subtitle: Text('${p.authorName} · ${timeAgo(p.submittedAt)}'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _open(p),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

/// Xem đầy đủ một bài chờ duyệt rồi Duyệt hoặc Từ chối (bắt buộc có lý do).
class AdminReviewDetailScreen extends StatefulWidget {
  const AdminReviewDetailScreen({super.key, required this.recipeId});
  final int recipeId;

  @override
  State<AdminReviewDetailScreen> createState() => _AdminReviewDetailScreenState();
}

class _AdminReviewDetailScreenState extends State<AdminReviewDetailScreen> {
  static const _quickReasons = [
    'Nội dung không phù hợp',
    'Nguyên liệu hoặc cách nấu không an toàn',
    'Thiếu thông tin, công thức không nấu được',
    'Ảnh không liên quan',
    'Quảng cáo hoặc spam',
  ];

  // Mục kiểm tra an toàn chỉ để đọc (KE_HOACH_CHIA_SE_CONG_THUC mục 3.5)
  static const _checklist = [
    'Có nguyên liệu độc hoặc không ăn được',
    'Nhiệt độ, thời gian nấu nguy hiểm (thịt gà, heo chưa chín)',
    'Thực phẩm dễ ngộ độc (nấm, sắn, đậu đỏ chưa chín)',
    'Nội dung phản cảm hoặc quảng cáo',
    'Ảnh không liên quan đến món',
  ];

  late final AdminRepository _repo;
  RecipeDetail? _recipe;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final services = Services.of(context);
    _repo = AdminRepository(services.api);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final recipe = await Services.of(context).recipes.getRecipe(widget.recipeId);
      if (mounted) setState(() => _recipe = recipe);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duyệt bài này?'),
        content: const Text('Bài sẽ hiện ở tab Cộng đồng cho mọi người.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Duyệt')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => _repo.approve(widget.recipeId), 'Đã duyệt bài');
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const ReasonDialog(reasons: _quickReasons),
    );
    if (reason == null) return;
    await _run(() => _repo.reject(widget.recipeId, reason), 'Đã từ chối bài');
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa bài này?'),
        content: const Text('Bài sẽ bị xóa khỏi hệ thống, tác giả sẽ không còn thấy bài.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => _repo.delete(widget.recipeId), 'Đã xóa bài');
  }

  Future<void> _run(Future<void> Function() action, String doneMessage) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _busy = true);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(doneMessage)));
      router.pop(true);
    } on ApiException catch (e) {
      // 409: bài đã được admin khác xử lý; quay về danh sách để thấy trạng thái mới
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      if (e.statusCode == 409 || e.statusCode == 404) router.pop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipe = _recipe;
    final pending = recipe?.status == 0;
    return Scaffold(
      appBar: AppBar(title: Text(recipe?.name ?? 'Duyệt bài')),
      body: _loading && recipe == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _content(recipe!),
      bottomNavigationBar: recipe == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    IconButton.outlined(
                      tooltip: 'Xóa',
                      onPressed: _busy ? null : _delete,
                      icon: const Icon(Icons.delete_outline),
                    ),
                    if (pending) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _reject,
                          icon: const Icon(Icons.close),
                          label: const Text('Từ chối'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _approve,
                          icon: const Icon(Icons.check),
                          label: const Text('Duyệt'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _content(RecipeDetail recipe) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (recipe.status != 0)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: ErrorBanner(message: 'Bài này đã được xử lý, không còn chờ duyệt.'),
          ),
        LayoutBuilder(
          builder: (context, c) =>
              RecipeImage(size: 200, width: c.maxWidth, imageUrl: recipe.imageUrl),
        ),
        const SizedBox(height: 16),
        Text(recipe.name, style: theme.textTheme.headlineSmall),
        Text('Tác giả: ${recipe.authorName ?? 'không rõ'}', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            InfoTag(icon: Icons.content_cut, text: 'Sơ chế ${recipe.prepMinutes} phút'),
            InfoTag(icon: Icons.local_fire_department, text: 'Nấu ${recipe.cookMinutes} phút'),
            InfoTag(icon: Icons.signal_cellular_alt, text: difficultyLabel(recipe.difficulty)),
            InfoTag(icon: Icons.people_outline, text: '${recipe.baseServings} người'),
          ],
        ),
        const SizedBox(height: 12),
        Text(recipe.description, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 16),
        Card(
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kiểm tra an toàn trước khi duyệt', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                for (final item in _checklist)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.fact_check_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Nguyên liệu (${recipe.ingredients.length})', style: theme.textTheme.titleLarge),
        for (final ing in recipe.ingredients)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(ing.isOptional ? '${ing.name} (tùy chọn)' : ing.name),
            trailing: Text('${ing.quantity} ${ing.unit}'),
          ),
        const SizedBox(height: 16),
        Text('Các bước (${recipe.steps.length})', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final step in recipe.steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 16, child: Text('${step.stepNumber}')),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(step.instruction, style: theme.textTheme.bodyLarge),
                      if (step.hasTimer)
                        InfoTag(
                            icon: Icons.timer_outlined,
                            text: formatDuration(step.timerSeconds)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Hỏi lý do bắt buộc (5 đến 500 ký tự), có sẵn vài lý do để chọn nhanh. Dùng cho Từ chối và Gỡ bài.
class ReasonDialog extends StatefulWidget {
  const ReasonDialog({
    super.key,
    required this.reasons,
    this.title = 'Từ chối bài',
    this.confirmLabel = 'Từ chối',
  });
  final List<String> reasons;
  final String title;
  final String confirmLabel;

  @override
  State<ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<ReasonDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _controller.text.trim();
    if (reason.length < 5) {
      setState(() => _error = 'Lý do phải từ 5 đến 500 ký tự');
      return;
    }
    Navigator.pop(context, reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              maxLength: 500,
              maxLines: 3,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: 'Lý do (bắt buộc)',
                errorText: _error,
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final r in widget.reasons)
                  ActionChip(
                    label: Text(r),
                    onPressed: () => setState(() {
                      _controller.text = r;
                      _error = null;
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
