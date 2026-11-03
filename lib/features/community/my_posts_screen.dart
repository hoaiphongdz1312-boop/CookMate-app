import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../../core/widgets.dart';
import '../recipes/recipe_image.dart';
import 'community_models.dart';
import 'community_repository.dart';

/// Bài của tôi: trạng thái từng bài, lý do bị từ chối, sửa lại và xóa.
class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({super.key});

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  late final CommunityRepository _repo;
  List<MyPost> _posts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = CommunityRepository(Services.of(context).api);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Mỗi người tối đa vài chục bài; lấy một trang lớn là đủ cho màn này
      final page = await _repo.mine(pageSize: 50);
      if (mounted) setState(() => _posts = page.items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(MyPost post) async {
    final changed = await context.push<bool>('/community/edit/${post.id}');
    if (changed == true && mounted) _load();
  }

  Future<void> _delete(MyPost post) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa bài này?'),
        content: Text(post.status == PostStatus.approved
            ? '"${post.name}" sẽ biến mất khỏi tab Cộng đồng.'
            : '"${post.name}" sẽ bị xóa.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.delete(post.id);
      if (!mounted) return;
      setState(() => _posts.removeWhere((p) => p.id == post.id));
      messenger.showSnackBar(const SnackBar(content: Text('Đã xóa bài')));
    } on ApiException catch (e) {
      if (mounted && e.statusCode == 404) setState(() => _posts.removeWhere((p) => p.id == post.id));
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bài của tôi')),
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
                              icon: Icons.post_add,
                              message: 'Bạn chưa chia sẻ công thức nào',
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _posts.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, i) => _MyPostCard(
                            post: _posts[i],
                            onOpen: () => context.push('/recipes/${_posts[i].id}'),
                            onEdit: () => _edit(_posts[i]),
                            onDelete: () => _delete(_posts[i]),
                          ),
                        ),
                ),
    );
  }
}

class _MyPostCard extends StatelessWidget {
  const _MyPostCard({
    required this.post,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final MyPost post;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (color, onColor, icon) = switch (post.status) {
      PostStatus.pending => (scheme.tertiaryContainer, scheme.onTertiaryContainer, Icons.hourglass_top),
      PostStatus.approved =>
        (scheme.primaryContainer, scheme.onPrimaryContainer, Icons.check_circle_outline),
      PostStatus.rejected => (scheme.errorContainer, scheme.onErrorContainer, Icons.block),
    };
    // Bài đã duyệt không sửa được (server trả 409): chỉ còn xóa
    final canEdit = post.status != PostStatus.approved;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RecipeImage(size: 72, imageUrl: post.imageUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(post.name, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Chip(
                          avatar: Icon(icon, size: 18, color: onColor),
                          label: Text(post.status.label, style: TextStyle(color: onColor)),
                          backgroundColor: color,
                          side: BorderSide.none,
                          visualDensity: VisualDensity.compact,
                        ),
                        if (post.submittedAt != null)
                          Text('Gửi ${timeAgo(post.submittedAt)}', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              if (post.status == PostStatus.rejected && post.rejectReason != null) ...[
                const SizedBox(height: 8),
                Text('Lý do: ${post.rejectReason}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error)),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canEdit)
                    TextButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(post.status == PostStatus.rejected ? 'Sửa và gửi lại' : 'Sửa'),
                    ),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Xóa'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
