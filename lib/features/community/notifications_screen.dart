import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../../core/widgets.dart';
import 'community_models.dart';
import 'community_repository.dart';

/// Thông báo kết quả duyệt bài. Mở màn này là đánh dấu đã đọc hết.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final CommunityRepository _repo;
  List<AppNotification> _items = [];
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
      final page = await _repo.notifications(pageSize: 50);
      if (mounted) setState(() => _items = page.items);
      // Giữ cờ chưa đọc trên danh sách đang hiện để người dùng còn thấy cái nào mới
      if (page.items.any((n) => !n.isRead)) await _repo.markAllNotificationsRead();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Thông báo')),
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
                            EmptyView(
                              icon: Icons.notifications_none,
                              message: 'Chưa có thông báo nào',
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final n = _items[i];
                            return ListTile(
                              tileColor: n.isRead ? null : scheme.primaryContainer.withValues(alpha: 0.35),
                              leading: Icon(
                                n.isPositive ? Icons.check_circle_outline : Icons.error_outline,
                                color: n.isPositive ? scheme.primary : scheme.error,
                              ),
                              title: Text(n.title),
                              subtitle: Text('${n.body}\n${timeAgo(n.createdAt)}'),
                              isThreeLine: true,
                              // Bài đã duyệt mở chi tiết; bài bị từ chối/gỡ xem lý do ở Bài của tôi
                              onTap: () => n.isPositive && n.recipeId != null
                                  ? context.push('/recipes/${n.recipeId}')
                                  : context.push('/community/mine'),
                            );
                          },
                        ),
                ),
    );
  }
}
