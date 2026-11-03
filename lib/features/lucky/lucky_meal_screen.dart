import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../../core/widgets.dart';
import '../recipes/recipe_image.dart';
import '../recipes/recipe_models.dart';
import '../recipes/recipe_repository.dart';

/// "Hôm nay ăn gì?": lọc danh mục, độ khó, thời gian rồi quay ngẫu nhiên một món hệ thống.
/// Món nào đã trúng trong phiên thì không quay lại nữa.
class LuckyMealScreen extends StatefulWidget {
  const LuckyMealScreen({super.key, this.spinDuration = const Duration(milliseconds: 1600)});

  /// Thời gian quay tối thiểu trước khi hiện món
  final Duration spinDuration;

  @override
  State<LuckyMealScreen> createState() => _LuckyMealScreenState();
}

class _LuckyMealScreenState extends State<LuckyMealScreen> {
  static const _timeOptions = [15, 30, 60];
  static const _tick = Duration(milliseconds: 90);

  late final RecipeRepository _repo;
  Timer? _ticker;

  List<Category> _categories = [];
  List<String> _reel = [];
  int? _categoryId;
  int? _difficulty;
  int? _maxMinutes;

  final _excluded = <int>[];
  RecipeSummary? _result;
  String? _reelText;
  bool _spinning = false;
  String? _message;
  bool _exhausted = false;

  @override
  void initState() {
    super.initState();
    _repo = Services.of(context).recipes;
    _loadOptions();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final categories = await _repo.getCategories();
      final page = await _repo.getRecipes(pageSize: 50);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _reel = page.items.map((r) => r.name).toList();
      });
    } on ApiException catch (_) {
      // Không có danh mục/tên món thì vẫn quay được, chỉ thiếu bộ lọc và chữ chạy
    }
  }

  void _filterChanged(VoidCallback change) {
    if (_spinning) return;
    setState(() {
      change();
      _excluded.clear();
      _result = null;
      _message = null;
      _exhausted = false;
    });
  }

  Future<void> _spin() async {
    if (_spinning) return;
    setState(() {
      _spinning = true;
      _message = null;
      _exhausted = false;
    });

    var i = 0;
    _ticker?.cancel();
    if (_reel.isNotEmpty) {
      _ticker = Timer.periodic(_tick, (_) {
        if (mounted) setState(() => _reelText = _reel[i++ % _reel.length]);
      });
    }

    RecipeSummary? picked;
    String? message;
    var exhausted = false;
    try {
      // Dừng đúng món server trả về: gọi API song song với thời gian quay tối thiểu
      final results = await Future.wait<Object?>([
        _repo.getRandom(
          categoryId: _categoryId,
          difficulty: _difficulty,
          maxMinutes: _maxMinutes,
          excludeIds: _excluded,
        ),
        Future<void>.delayed(widget.spinDuration),
      ]);
      picked = results[0] as RecipeSummary;
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        exhausted = true;
        message = _excluded.isEmpty
            ? 'Không có món nào phù hợp, hãy thử nới bộ lọc.'
            : 'Bạn đã xem hết các món phù hợp.';
      } else {
        message = e.message;
      }
    }

    _ticker?.cancel();
    if (!mounted) return;
    setState(() {
      _spinning = false;
      _reelText = null;
      if (picked != null) {
        _result = picked;
        _excluded.add(picked.id);
      } else {
        _result = null;
      }
      _message = message;
      _exhausted = exhausted;
    });
  }

  void _resetExcluded() {
    setState(() {
      _excluded.clear();
      _message = null;
      _exhausted = false;
    });
    _spin();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Hôm nay ăn gì?')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _chipRow('Độ khó', [
            for (final d in [1, 2, 3])
              ChoiceChip(
                label: Text(difficultyLabel(d)),
                selected: _difficulty == d,
                onSelected: (on) => _filterChanged(() => _difficulty = on ? d : null),
              ),
          ]),
          _chipRow('Thời gian tối đa', [
            for (final m in _timeOptions)
              ChoiceChip(
                label: Text('$m phút'),
                selected: _maxMinutes == m,
                onSelected: (on) => _filterChanged(() => _maxMinutes = on ? m : null),
              ),
          ]),
          if (_categories.isNotEmpty)
            _chipRow('Danh mục', [
              for (final c in _categories)
                ChoiceChip(
                  label: Text(c.name),
                  selected: _categoryId == c.id,
                  onSelected: (on) => _filterChanged(() => _categoryId = on ? c.id : null),
                ),
            ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: _spinning ? null : _spin,
              icon: const Icon(Icons.casino_outlined),
              label: Text(_result == null ? 'QUAY NGAY' : 'THỬ MÓN KHÁC'),
            ),
          ),
          const SizedBox(height: 24),
          if (_spinning) _spinningView(theme),
          if (!_spinning && _result != null) _resultCard(theme, _result!),
          if (!_spinning && _message != null) _messageView(),
        ],
      ),
    );
  }

  Widget _chipRow(String title, List<Widget> chips) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
        ),
      );

  Widget _spinningView(ThemeData theme) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_reelText ?? 'Đang chọn món...',
                  textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            ],
          ),
        ),
      );

  Widget _resultCard(ThemeData theme, RecipeSummary r) => Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RecipeImage(size: 180, width: double.infinity, imageUrl: r.imageUrl),
              const SizedBox(height: 12),
              Text(r.name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('${r.totalMinutes} phút · ${difficultyLabel(r.difficulty)}',
                  style: theme.textTheme.bodyMedium),
              if (r.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(r.description, maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.push('/recipes/${r.id}'),
                      child: const Text('Xem công thức'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => context.push('/recipes/${r.id}/cook'),
                      child: const Text('Nấu món này'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _messageView() => Column(
        children: [
          if (_exhausted)
            EmptyView(message: _message!)
          else
            ErrorBanner(message: _message!),
          if (_exhausted && _excluded.isNotEmpty) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _resetExcluded, child: const Text('Quay lại từ đầu')),
          ],
        ],
      );
}
