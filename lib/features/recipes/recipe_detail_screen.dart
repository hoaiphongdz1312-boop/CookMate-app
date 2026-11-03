import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../../core/widgets.dart';
import 'portion.dart';
import '../community/community_models.dart';
import '../community/community_repository.dart';
import '../community/moderation_actions.dart';
import 'recipe_image.dart';
import 'recipe_list_screen.dart' show InfoTag;
import 'recipe_models.dart';
import 'step_instruction.dart';

class RecipeDetailScreen extends StatefulWidget {
  const RecipeDetailScreen({super.key, required this.recipeId});
  final int recipeId;

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  RecipeDetail? _recipe;
  String? _error;
  bool _loading = true;
  int? _servings; // null = chưa chọn, dùng khẩu phần gốc của món

  @override
  void initState() {
    super.initState();
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
      if (mounted) {
        setState(() => _error =
            e.statusCode == 404 ? 'Không tìm thấy công thức này' : e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Menu Báo cáo / Chặn: chỉ với bài đang hiển thị của người khác. Admin xử lý vi phạm ở màn admin.
  Widget? _moderationMenu(RecipeDetail recipe) {
    final me = Services.of(context).auth.user;
    if (me == null || me.isAdmin) return null;
    final isMine = recipe.authorId == me.id;
    // status chỉ có giá trị khi người xem là tác giả; null = bài đã duyệt của người khác
    final visible = recipe.status == null || recipe.status == 1;
    if (isMine || !visible) return null;
    final canBlock = recipe.isCommunity;
    return PopupMenuButton<String>(
      tooltip: 'Tùy chọn',
      onSelected: (value) async {
        final repo = CommunityRepository(Services.of(context).api);
        if (value == 'report') {
          await reportRecipe(context, repo, recipe.id);
        } else if (value == 'block') {
          final router = GoRouter.of(context);
          final blocked = await blockUser(context, repo, recipe.authorId!, recipe.authorName);
          // Về feed và báo để tải lại, bài của người bị chặn biến mất
          if (blocked && mounted) router.pop(true);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'report',
          child: ListTile(
            leading: Icon(Icons.flag_outlined),
            title: Text('Báo cáo vi phạm'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (canBlock)
          PopupMenuItem(
            value: 'block',
            child: ListTile(
              leading: const Icon(Icons.block),
              title: Text('Chặn ${recipe.authorName ?? 'người dùng'}'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final recipe = _recipe;
    final menu = recipe == null ? null : _moderationMenu(recipe);
    return Scaffold(
      appBar: AppBar(
        title: Text(recipe?.name ?? 'Chi tiết món'),
        actions: [?menu],
      ),
      body: _loading && recipe == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(onRefresh: _load, child: _buildContent(recipe!)),
      bottomNavigationBar: recipe == null || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Bắt đầu nấu'),
                  onPressed: () => context.push(
                    '/recipes/${recipe.id}/cook?servings=${_servings ?? recipe.baseServings}',
                  ),
                ),
              ),
            ),
    );
  }

  Widget _servingsPicker(RecipeDetail recipe, int servings) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text('Nguyên liệu cho $servings người', style: theme.textTheme.titleLarge),
        ),
        IconButton.outlined(
          tooltip: 'Giảm khẩu phần',
          onPressed: servings > minServings
              ? () => setState(() => _servings = servings - 1)
              : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 40,
          child: Text('$servings',
              textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
        ),
        IconButton.outlined(
          tooltip: 'Tăng khẩu phần',
          onPressed: servings < maxServings
              ? () => setState(() => _servings = servings + 1)
              : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  /// Chỉ tác giả và admin nhận được status. Bài đã duyệt không cần banner.
  Widget _statusBanner(RecipeDetail recipe) {
    final code = recipe.status;
    if (code == null || code == 1) return const SizedBox.shrink();
    final status = PostStatus.fromCode(code);
    final scheme = Theme.of(context).colorScheme;
    final rejected = status == PostStatus.rejected;
    final text = rejected
        ? 'Bài bị từ chối: ${recipe.rejectReason ?? 'không có lý do'}'
        : 'Bài đang chờ admin duyệt, chưa hiện ở tab Cộng đồng.';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: rejected ? scheme.errorContainer : scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(rejected ? Icons.block : Icons.hourglass_top,
                  color: rejected ? scheme.onErrorContainer : scheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        color: rejected
                            ? scheme.onErrorContainer
                            : scheme.onTertiaryContainer)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(RecipeDetail recipe) {
    final theme = Theme.of(context);
    final servings = _servings ?? recipe.baseServings;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _statusBanner(recipe),
        if (uploadedImageUrl(recipe.imageUrl) != null) ...[
          RecipeImage(size: 200, width: double.infinity, imageUrl: recipe.imageUrl),
          const SizedBox(height: 16),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (uploadedImageUrl(recipe.imageUrl) == null) ...[
              RecipeImage(size: 112, imageUrl: recipe.imageUrl),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(recipe.name, style: theme.textTheme.headlineSmall),
                  if (recipe.isCommunity && recipe.authorName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Công thức do ${recipe.authorName} chia sẻ',
                          style: theme.textTheme.bodyMedium),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      InfoTag(
                          icon: Icons.content_cut,
                          text: 'Sơ chế ${recipe.prepMinutes} phút'),
                      InfoTag(
                          icon: Icons.local_fire_department,
                          text: 'Nấu ${recipe.cookMinutes} phút'),
                      InfoTag(
                          icon: Icons.signal_cellular_alt,
                          text: difficultyLabel(recipe.difficulty)),
                      InfoTag(
                          icon: Icons.people_outline,
                          text: '${recipe.baseServings} người'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(recipe.description, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 24),
        _servingsPicker(recipe, servings),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (final ing in recipe.ingredients)
                ListTile(
                  leading: Icon(
                    ing.isOptional ? Icons.add_circle_outline : Icons.check_circle_outline,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(ing.name, style: theme.textTheme.titleMedium),
                  subtitle: ing.isOptional ? const Text('Tùy chọn') : null,
                  trailing: Text(
                      '${formatQuantity(scaleQuantity(quantity: ing.quantity, baseServings: recipe.baseServings, servings: servings, unit: ing.unit))} ${ing.unit}',
                      style: theme.textTheme.titleMedium),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Các bước (${recipe.steps.length})', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final step in recipe.steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  child: Text('${step.stepNumber}'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StepInstruction(text: step.instruction),
                      if (step.hasTimer)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: InfoTag(
                              icon: Icons.timer_outlined,
                              text: formatDuration(step.timerSeconds)),
                        ),
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


String formatDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  if (m == 0) return '$s giây';
  if (s == 0) return '$m phút';
  return '$m phút $s giây';
}
