import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../../core/widgets.dart';
import '../recipes/recipe_image.dart';
import '../recipes/recipe_list_screen.dart' show InfoTag;
import '../recipes/recipe_models.dart';
import 'community_models.dart';
import 'community_repository.dart';

/// Tab Cộng đồng: công thức người dùng chia sẻ và đã được admin duyệt.
class CommunityFeedScreen extends StatefulWidget {
  const CommunityFeedScreen({super.key});

  @override
  State<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends State<CommunityFeedScreen> {
  static const _searchDelay = Duration(milliseconds: 400);
  static const _pageSize = 10;

  late final CommunityRepository _repo;
  final _searchController = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  List<Category> _categories = [];
  final List<CommunityPost> _posts = [];
  int? _categoryId;
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;

  // Bỏ kết quả của request cũ nếu người dùng đã đổi bộ lọc
  int _requestId = 0;
  bool _wasActive = true;

  @override
  void initState() {
    super.initState();
    final services = Services.of(context);
    _repo = CommunityRepository(services.api);
    _scroll.addListener(_onScroll);
    _loadCategories(services);
    _load(reset: true);
    _loadUnread();
  }

  // Số thông báo chưa đọc (kết quả duyệt bài). Admin không đăng bài nên không có thông báo.
  int _unread = 0;

  Future<void> _loadUnread() async {
    if (Services.of(context).auth.user?.isAdmin == true) return;
    try {
      final count = await _repo.unreadNotificationCount();
      if (mounted) setState(() => _unread = count);
    } on ApiException catch (_) {}
  }

  Future<void> _openNotifications() async {
    await context.push('/notifications');
    if (mounted) _loadUnread();
  }

  Future<void> _openPost(CommunityPost post) async {
    // Chi tiết trả true khi người xem vừa chặn tác giả: tải lại để bài của họ biến mất
    final changed = await context.push<bool>('/recipes/${post.id}');
    if (changed == true && mounted) _load(reset: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Tab được giữ sống khi ẩn; quay lại tab thì tải lại để thấy bài mới được duyệt
    final active = TickerMode.valuesOf(context).enabled;
    if (active && !_wasActive && !_loading) {
      _load(reset: true);
      _loadUnread();
    }
    _wasActive = active;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadCategories(Services services) async {
    try {
      final categories = await services.recipes.getCategories();
      if (mounted) setState(() => _categories = categories);
    } on ApiException catch (_) {}
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 300 && _hasMore && !_loading && _error == null) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    final requestId = reset ? ++_requestId : _requestId;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repo.feed(
        search: _searchController.text,
        categoryId: _categoryId,
        page: page,
        pageSize: _pageSize,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        if (reset) _posts.clear();
        _posts.addAll(result.items);
        _page = result.page;
        _hasMore = result.hasMore;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(_searchDelay, () => _load(reset: true));
    setState(() {});
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    _load(reset: true);
  }

  Future<void> _delete(CommunityPost post) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa bài này?'),
        content: Text('"${post.name}" sẽ biến mất khỏi tab Cộng đồng.'),
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
      // 404: bài đã bị xóa ở nơi khác nên cũng bỏ khỏi danh sách
      if (mounted && e.statusCode == 404) setState(() => _posts.removeWhere((p) => p.id == post.id));
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _share() async {
    final created = await context.push<bool>('/community/new');
    if (created != true || !mounted) return;
    // Bài đăng thẳng (tác giả đủ ngưỡng tin cậy) thì đã có trên feed
    _load(reset: true);
    context.push('/community/mine');
  }

  String? _categoryName(int id) {
    for (final c in _categories) {
      if (c.id == id) return c.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = Services.of(context).auth;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cộng đồng'),
        actions: [
          // Admin không chia sẻ bài cộng đồng (server trả 403), nên không có Bài của tôi
          ListenableBuilder(
            listenable: auth,
            builder: (context, _) => auth.user?.isAdmin == true
                ? const SizedBox.shrink()
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Thông báo',
                        icon: Badge(
                          isLabelVisible: _unread > 0,
                          label: Text('$_unread'),
                          child: const Icon(Icons.notifications_outlined),
                        ),
                        onPressed: _openNotifications,
                      ),
                      IconButton(
                        tooltip: 'Bài của tôi',
                        icon: const Icon(Icons.folder_shared_outlined),
                        onPressed: () => context.push('/community/mine'),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: ListenableBuilder(
        listenable: auth,
        builder: (context, _) => auth.user?.isAdmin == true
            ? const SizedBox.shrink()
            : FloatingActionButton.extended(
                onPressed: _share,
                icon: const Icon(Icons.add),
                label: const Text('Chia sẻ công thức'),
              ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Tìm công thức của cộng đồng',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Xóa',
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                      ),
              ),
            ),
          ),
          if (_categories.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  for (final c in _categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(c.name),
                        selected: _categoryId == c.id,
                        onSelected: (selected) {
                          setState(() => _categoryId = selected ? c.id : null);
                          _load(reset: true);
                        },
                      ),
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_posts.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_posts.isEmpty && _error != null) {
      return ErrorView(message: _error!, onRetry: () => _load(reset: true));
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: _posts.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 80),
                EmptyView(
                  icon: Icons.groups_outlined,
                  message: 'Chưa có công thức nào. Hãy là người đầu tiên chia sẻ!',
                ),
              ],
            )
          : ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              // Chừa chỗ cho nút nổi để không che thẻ cuối
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: _posts.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                if (i == _posts.length) return _footer();
                final post = _posts[i];
                final me = Services.of(context).auth.user;
                final canDelete = me != null && (me.isAdmin || post.authorId == me.id);
                return _PostCard(
                  post: post,
                  onDelete: canDelete ? () => _delete(post) : null,
                  categoryName: _categoryName(post.categoryId),
                  onTap: () => _openPost(post),
                );
              },
            ),
    );
  }

  Widget _footer() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Center(
        child: TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text('$_error. Thử lại'),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.categoryName,
    required this.onTap,
    this.onDelete,
  });

  final CommunityPost post;
  final VoidCallback? onDelete;
  final String? categoryName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => RecipeImage(
                size: 180,
                width: constraints.maxWidth,
                imageUrl: post.imageUrl,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(post.name, style: theme.textTheme.titleLarge)),
                      if (onDelete != null)
                        TextButton.icon(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Xóa'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      'Đăng bởi ${post.authorName ?? 'ẩn danh'}',
                      if (post.publishedAt != null) timeAgo(post.publishedAt),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      InfoTag(icon: Icons.schedule, text: '${post.totalMinutes} phút'),
                      InfoTag(
                          icon: Icons.signal_cellular_alt,
                          text: difficultyLabel(post.difficulty)),
                      if (categoryName != null)
                        InfoTag(icon: Icons.category_outlined, text: categoryName!),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
