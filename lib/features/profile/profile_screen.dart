import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../admin/admin_repository.dart';
import '../cooking/cooking_repository.dart';
import '../face/face_repository.dart';
import '../cooking/voice_service.dart' show VoiceStatus;

/// Hồ sơ: thông tin tài khoản và quản lý dữ liệu khuôn mặt.
/// Phần tiến độ nấu ăn bổ sung ở bước F9.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _busy = false;
  Progress? _progress;
  String? _progressError;

  @override
  void initState() {
    super.initState();
    // Lấy hasFace và tiến độ mới nhất từ server
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final auth = Services.of(context).auth;
      _loadProgress();
      await auth.refreshUser();
      if (mounted) _loadPendingCount();
    });
  }

  // Số bài chờ duyệt và số bài bị báo cáo, chỉ admin mới gọi (server trả 403 với user thường)
  int? _pendingCount;
  int? _reportCount;

  Future<void> _loadPendingCount() async {
    final services = Services.of(context);
    if (services.auth.user?.isAdmin != true) return;
    final repo = AdminRepository(services.api);
    try {
      final count = await repo.pendingCount();
      if (mounted) setState(() => _pendingCount = count);
    } on ApiException catch (_) {}
    try {
      final count = await repo.reportCount();
      if (mounted) setState(() => _reportCount = count);
    } on ApiException catch (_) {}
  }

  bool _wasActive = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Tab được giữ sống khi ẩn (TickerMode tắt); quay lại tab thì tải lại tiến độ
    final active = TickerMode.valuesOf(context).enabled;
    if (active && !_wasActive) {
      _loadProgress();
      _loadPendingCount();
    }
    _wasActive = active;
  }

  Future<void> _loadProgress() async {
    setState(() => _progressError = null);
    try {
      final p = await CookingRepository(Services.of(context).api).progress();
      if (mounted) setState(() => _progress = p);
    } on ApiException catch (e) {
      if (mounted) setState(() => _progressError = e.message);
    }
  }

  Future<void> _confirmLogout() async {
    final auth = Services.of(context).auth;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Đăng xuất')),
        ],
      ),
    );
    if (ok == true) await auth.logout();
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _progressSection(ThemeData theme) {
    final p = _progress;
    if (_progressError != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(_progressError!),
          trailing: TextButton(onPressed: _loadProgress, child: const Text('Thử lại')),
        ),
      );
    }
    if (p == null) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatCard(value: p.completedCount, label: 'Món đã nấu'),
        if (p.inProgress.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Đang nấu dở', style: theme.textTheme.titleMedium),
          for (final i in p.inProgress)
            Card(
              child: ListTile(
                title: Text(i.recipeName),
                subtitle: Text('Bước ${i.currentStep}/${i.totalSteps}'),
                trailing: const Icon(Icons.play_arrow),
                onTap: () async {
                  await context.push('/recipes/${i.recipeId}/cook');
                  if (mounted) _loadProgress();
                },
              ),
            ),
        ],
        if (p.history.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Lịch sử', style: theme.textTheme.titleMedium),
          for (final h in p.history)
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text(h.recipeName),
              subtitle: Text(_date(h.completedAt)),
              onTap: () => context.push('/recipes/${h.recipeId}'),
            ),
        ],
      ],
    );
  }

  Future<void> _deleteFace() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa dữ liệu khuôn mặt?'),
        content: const Text(
            'Bạn sẽ không đăng nhập bằng khuôn mặt được nữa cho tới khi đăng ký lại.'),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
            onPressed: () => context.pop(true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final services = Services.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await FaceRepository(services.api).delete();
      await services.auth.refreshUser();
      messenger.showSnackBar(const SnackBar(content: Text('Đã xóa dữ liệu khuôn mặt')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Services.of(context).auth;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hồ sơ'),
        actions: [
          IconButton(
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout),
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: auth,
        builder: (context, _) {
          final user = auth.user;
          final initial = (user?.fullName.trim().isNotEmpty ?? false)
              ? user!.fullName.trim()[0].toUpperCase()
              : '?';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 44,
                  child: Text(initial, style: theme.textTheme.headlineMedium),
                ),
              ),
              const SizedBox(height: 12),
              Text(user?.fullName ?? '...',
                  textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
              Text(user?.email ?? '',
                  textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 24),
              _progressSection(theme),
              const SizedBox(height: 24),
              ListenableBuilder(
                listenable: Services.of(context).voice,
                builder: (context, _) {
                  final voice = Services.of(context).voice;
                  final failed = voice.status == VoiceStatus.unavailable;
                  return Card(
                    child: SwitchListTile(
                      secondary: Icon(failed ? Icons.mic_off : Icons.mic_none),
                      title: const Text('Nghe "Bếp ơi"'),
                      subtitle: Text(failed
                          ? (voice.error ?? 'Giọng nói không dùng được')
                          : voice.enabled
                              ? 'Đang nghe khi app mở. Nói "Bếp ơi" rồi ra lệnh.'
                              : 'Bật để điều khiển bằng giọng nói khi tay bận.'),
                      value: voice.enabled,
                      onChanged: (_) => voice.toggle(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.restaurant_menu),
                  title: const Text('Khẩu vị của bạn'),
                  subtitle: Text(user?.tastes?.isNotEmpty == true
                      ? user!.tastes!.join(', ')
                      : 'Chưa chọn'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/tastes?edit=1'),
                ),
              ),
              const SizedBox(height: 16),
              if (user?.isAdmin == true) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: Text(_pendingCount == null
                        ? 'Duyệt công thức'
                        : 'Duyệt công thức ($_pendingCount)'),
                    subtitle: const Text('Bài người dùng chia sẻ đang chờ kiểm tra'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await context.push('/admin/review');
                      if (mounted) _loadPendingCount();
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: Text(_reportCount == null
                        ? 'Báo cáo vi phạm'
                        : 'Báo cáo vi phạm ($_reportCount)'),
                    subtitle: const Text('Bài bị người dùng báo cáo, chờ xử lý'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await context.push('/admin/reports');
                      if (mounted) _loadPendingCount();
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_off_outlined),
                    title: const Text('Người dùng đã chặn'),
                    subtitle: const Text('Bỏ chặn để thấy lại bài của họ'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/blocked-users'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.face_retouching_natural),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('Đăng nhập bằng khuôn mặt',
                                style: theme.textTheme.titleMedium),
                          ),
                          if (user != null)
                            Chip(
                              label: Text(user.hasFace ? 'Đã đăng ký' : 'Chưa đăng ký'),
                              avatar: Icon(
                                user.hasFace ? Icons.check_circle : Icons.info_outline,
                                size: 18,
                                color: user.hasFace ? Colors.green : null,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(user == null
                          ? 'Đang tải...'
                          : user.hasFace
                              ? 'Bạn có thể đăng nhập bằng khuôn mặt ở màn hình đăng nhập.'
                              : 'Đăng ký để lần sau chỉ cần nhìn vào camera và chớp mắt. '
                                  'Chỉ lưu vector đặc trưng, không lưu ảnh.'),
                      const SizedBox(height: 16),
                      if (user != null && !user.hasFace)
                        FilledButton.icon(
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: const Text('Đăng ký khuôn mặt'),
                          onPressed: () => context.push('/face-enroll'),
                        ),
                      if (user != null && user.hasFace) ...[
                        OutlinedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Đăng ký lại khuôn mặt'),
                          onPressed: _busy ? null : () => context.push('/face-enroll'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Xóa dữ liệu khuôn mặt'),
                          onPressed: _busy ? null : _deleteFace,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('$value', style: theme.textTheme.headlineLarge),
            Text(label, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
