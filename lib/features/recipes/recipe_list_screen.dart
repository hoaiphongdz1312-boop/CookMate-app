import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../../core/widgets.dart';
import 'recipe_image.dart';
import 'recipe_models.dart';
import 'recipe_repository.dart';

/// Màn chính: danh sách công thức, tìm theo tên, lọc danh mục và độ khó.
class RecipeListScreen extends StatefulWidget {
  const RecipeListScreen({super.key});

  @override
  State<RecipeListScreen> createState() => _RecipeListScreenState();
}

class _RecipeListScreenState extends State<RecipeListScreen> {
  static const _searchDelay = Duration(milliseconds: 400);
  // 15 món của bản nước rút nằm gọn trong 1 trang (server cho tối đa 50)
  static const _pageSize = 50;

  late final RecipeRepository _repo;
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Category> _categories = [];
  List<RecipeSummary> _recipes = [];
  List<RecipeSummary> _recommended = [];
  int? _categoryId;
  int? _difficulty;
  bool _loading = true;
  String? _error;

  // Bỏ kết quả của request cũ nếu người dùng đã đổi bộ lọc
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _repo = Services.of(context).recipes;
    _loadCategories();
    _loadRecipes();
    _loadRecommended();
  }

  bool _wasActive = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Tab được giữ sống khi ẩn; quay lại tab thì tải lại để thấy công thức admin mới thêm
    final active = TickerMode.valuesOf(context).enabled;
    if (active && !_wasActive && !_loading) {
      _loadRecipes();
      _loadRecommended();
    }
    _wasActive = active;
  }

  Future<void> _addRecipe() async {
    final added = await context.push<bool>('/admin/recipes/new');
    if (added == true && mounted) _loadRecipes();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _repo.getCategories();
      if (mounted) setState(() => _categories = categories);
    } on ApiException catch (_) {
      // Không có danh mục thì vẫn dùng được tìm kiếm; lỗi mạng đã hiện ở danh sách
    }
  }

  // Lỗi mạng thì bỏ qua mục gợi ý; danh sách chính đã có thông báo lỗi riêng
  Future<void> _loadRecommended() async {
    try {
      final items = await _repo.getRecommended();
      if (mounted) setState(() => _recommended = items);
    } on ApiException catch (_) {}
  }

  Future<void> _loadRecipes() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repo.getRecipes(
        search: _searchController.text,
        categoryId: _categoryId,
        difficulty: _difficulty,
        pageSize: _pageSize,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _recipes = page.items;
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

  Future<void> _refresh() async {
    if (_categories.isEmpty) unawaited(_loadCategories());
    unawaited(_loadRecommended());
    await _loadRecipes();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(_searchDelay, _loadRecipes);
    setState(() {}); // cập nhật nút xóa trong ô tìm kiếm
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    _loadRecipes();
  }

  @override
  Widget build(BuildContext context) {
    final auth = Services.of(context).auth;
    return Scaffold(
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: auth,
          builder: (context, _) {
            final name = auth.user?.fullName;
            return Text(name == null ? 'CookMate' : 'Chào $name');
          },
        ),
      ),
      // Chỉ admin thêm được công thức hệ thống
      floatingActionButton: ListenableBuilder(
        listenable: auth,
        builder: (context, _) => auth.user?.isAdmin == true
            ? FloatingActionButton.extended(
                onPressed: _addRecipe,
                icon: const Icon(Icons.add),
                label: const Text('Thêm công thức'),
              )
            : const SizedBox.shrink(),
      ),
      body: Column(
        children: [
          // Mời đăng ký khuôn mặt khi tài khoản chưa có (chỉ hiện khi đã biết chắc hasFace = false)
          ListenableBuilder(
            listenable: auth,
            builder: (context, _) {
              final user = auth.user;
              if (user == null || user.hasFace) return const SizedBox.shrink();
              return MaterialBanner(
                leading: const Icon(Icons.face_retouching_natural),
                content: const Text('Đăng ký khuôn mặt để lần sau đăng nhập nhanh hơn.'),
                actions: [
                  TextButton(
                    onPressed: () => context.push('/face-enroll'),
                    child: const Text('Đăng ký ngay'),
                  ),
                ],
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => context.push('/lucky'),
                icon: const Icon(Icons.casino_outlined),
                label: const Text('Hôm nay ăn gì?'),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Tìm món, ví dụ: thịt kho',
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
          _buildFilters(),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final d in [1, 2, 3])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(difficultyLabel(d)),
                selected: _difficulty == d,
                onSelected: (selected) {
                  setState(() => _difficulty = selected ? d : null);
                  _loadRecipes();
                },
              ),
            ),
          if (_categories.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: VerticalDivider(width: 1),
            ),
          for (final c in _categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(c.name),
                selected: _categoryId == c.id,
                onSelected: (selected) {
                  setState(() => _categoryId = selected ? c.id : null);
                  _loadRecipes();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _recipes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _refresh);
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: _recipes.isEmpty
          // Bọc trong ListView để vẫn kéo xuống tải lại được khi trống
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 80),
                EmptyView(message: 'Không có món nào phù hợp'),
              ],
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (_showRecommended) _buildRecommended(),
                for (final r in _recipes) ...[
                  _RecipeCard(
                    recipe: r,
                    categoryName: _categoryName(r.categoryId),
                    onTap: () => context.push('/recipes/${r.id}'),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }

  // Chỉ hiện khi không tìm kiếm/lọc, để danh sách đúng với điều người dùng đang tìm
  bool get _showRecommended =>
      _recommended.isNotEmpty &&
      _searchController.text.trim().isEmpty &&
      _categoryId == null &&
      _difficulty == null;

  Widget _buildRecommended() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dành cho bạn', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _recommended.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final r = _recommended[i];
                return SizedBox(
                  width: 150,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.push('/recipes/${r.id}'),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RecipeImage(size: 72, imageUrl: r.imageUrl),
                            const SizedBox(height: 8),
                            Text(r.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }

  String? _categoryName(int id) {
    for (final c in _categories) {
      if (c.id == id) return c.name;
    }
    return null;
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({
    required this.recipe,
    required this.categoryName,
    required this.onTap,
  });

  final RecipeSummary recipe;
  final String? categoryName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RecipeImage(size: 88, imageUrl: recipe.imageUrl),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(recipe.name, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      recipe.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        InfoTag(
                            icon: Icons.schedule,
                            text: '${recipe.totalMinutes} phút'),
                        InfoTag(
                            icon: Icons.signal_cellular_alt,
                            text: difficultyLabel(recipe.difficulty)),
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
      ),
    );
  }
}

class InfoTag extends StatelessWidget {
  const InfoTag({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: style?.color),
        const SizedBox(width: 4),
        Text(text, style: style),
      ],
    );
  }
}
