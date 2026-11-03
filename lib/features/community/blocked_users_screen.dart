import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../../core/widgets.dart';
import 'community_models.dart';
import 'community_repository.dart';

/// Danh sách người mình đã chặn, bỏ chặn được từng người.
class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  late final CommunityRepository _repo;
  List<BlockedUser> _users = [];
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
      final users = await _repo.blockedUsers();
      if (mounted) setState(() => _users = users);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(BlockedUser user) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.unblock(user.id);
      if (!mounted) return;
      setState(() => _users.removeWhere((u) => u.id == user.id));
      messenger.showSnackBar(SnackBar(content: Text('Đã bỏ chặn ${user.fullName}')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Người dùng đã chặn')),
      body: _loading && _users.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _users.isEmpty
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _users.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 80),
                            EmptyView(icon: Icons.person_off_outlined, message: 'Bạn chưa chặn ai'),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _users.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final u = _users[i];
                            return ListTile(
                              leading: const Icon(Icons.person_off_outlined),
                              title: Text(u.fullName),
                              subtitle: Text('Đã chặn ${timeAgo(u.blockedAt)}'),
                              trailing: TextButton(
                                onPressed: () => _unblock(u),
                                child: const Text('Bỏ chặn'),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
