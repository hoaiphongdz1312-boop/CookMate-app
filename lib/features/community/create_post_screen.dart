import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../../core/widgets.dart';
import '../admin/admin_repository.dart';
import '../recipes/recipe_image.dart';
import '../recipes/recipe_models.dart';
import 'community_models.dart';
import 'community_repository.dart';

/// Form tạo bài chia sẻ, hoặc sửa bài chờ duyệt/bị từ chối khi có [editId].
/// Bấm Chia sẻ là gửi duyệt luôn, không có bản nháp.
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key, this.editId, this.systemRecipe = false});
  final int? editId;

  /// Admin thêm công thức hệ thống: đăng thẳng, không qua duyệt.
  final bool systemRecipe;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  late final CommunityRepository _repo;
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _prep = TextEditingController(text: '0');
  final _cook = TextEditingController(text: '0');

  PostDraft _draft = PostDraft();
  List<Category> _categories = [];
  bool _loading = true;
  bool _busy = false;
  bool _uploading = false;
  String? _loadError;
  String? _error;

  bool get _editing => widget.editId != null;

  @override
  void initState() {
    super.initState();
    _repo = CommunityRepository(Services.of(context).api);
    _init();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _prep.dispose();
    _cook.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final recipes = Services.of(context).recipes;
    try {
      final categories = await recipes.getCategories();
      PostDraft draft = _draft;
      if (_editing) {
        draft = _draftFrom(await recipes.getRecipe(widget.editId!));
      }
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _draft = draft;
        _name.text = draft.name;
        _description.text = draft.description;
        _prep.text = '${draft.prepMinutes}';
        _cook.text = '${draft.cookMinutes}';
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.message;
          _loading = false;
        });
      }
    }
  }

  PostDraft _draftFrom(RecipeDetail r) => PostDraft(
        name: r.name,
        description: r.description,
        imageUrl: r.imageUrl,
        difficulty: r.difficulty,
        prepMinutes: r.prepMinutes,
        cookMinutes: r.cookMinutes,
        baseServings: r.baseServings,
        categoryId: r.categoryId,
        ingredients: [
          for (final i in r.ingredients)
            IngredientDraft(
              name: i.name,
              quantity: _formatNumber(i.quantity),
              unit: i.unit,
              isOptional: i.isOptional,
            ),
        ],
        steps: [
          for (final s in r.steps)
            StepDraft(instruction: s.instruction, timerMinutes: (s.timerSeconds / 60).ceil()),
        ],
      );

  static String _formatNumber(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Future<void> _pickImage() async {
    final messenger = ScaffoldMessenger.of(context);
    // Trình chọn ảnh của hệ thống dùng micro/camera: nghỉ nghe "bếp ơi" trong lúc đó
    final voice = Services.of(context).voice..hold(this);
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
    } finally {
      voice.release(this);
    }
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final url = await _repo.uploadImage(file.path);
      if (mounted) setState(() => _draft.imageUrl = url);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    _draft
      ..name = _name.text
      ..description = _description.text
      ..prepMinutes = int.tryParse(_prep.text.trim()) ?? -1
      ..cookMinutes = int.tryParse(_cook.text.trim()) ?? -1;
    final problem = _draft.validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.systemRecipe
            ? 'Thêm công thức?'
            : _editing
                ? 'Gửi lại để duyệt?'
                : 'Chia sẻ công thức?'),
        content: Text(widget.systemRecipe
            ? 'Công thức sẽ hiện ngay cho mọi người ở tab Công thức.'
            : _editing
                ? 'Bài sẽ được admin kiểm tra lại trước khi hiển thị cho mọi người.'
                : 'Bài của thành viên mới được admin kiểm tra trước khi hiển thị. '
                    'Khi bạn đã có 3 bài được duyệt, bài mới sẽ đăng ngay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(widget.systemRecipe ? 'Thêm' : 'Chia sẻ')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      String done;
      if (widget.systemRecipe) {
        await AdminRepository(Services.of(context).api).createRecipe(_draft);
        done = 'Đã thêm công thức';
      } else if (_editing) {
        await _repo.update(widget.editId!, _draft);
        done = 'Đã gửi lại, bài đang chờ duyệt';
      } else {
        final post = await _repo.create(_draft);
        done = createdMessage(post.status);
      }
      messenger.showSnackBar(SnackBar(content: Text(done)));
      if (mounted) context.pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.systemRecipe
              ? 'Thêm công thức'
              : _editing
                  ? 'Sửa bài'
                  : 'Chia sẻ công thức')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? ErrorView(message: _loadError!, onRetry: _init)
              : _form(),
      bottomNavigationBar: _loading || _loadError != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  label: Text(widget.systemRecipe ? 'Thêm công thức' : 'Chia sẻ'),
                  onPressed: _busy || _uploading ? null : _submit,
                ),
              ),
            ),
    );
  }

  Widget _form() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _name,
          maxLength: PostLimits.maxName,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Tên món'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _description,
          maxLength: PostLimits.maxDescription,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Mô tả'),
        ),
        const SizedBox(height: 8),
        _imageSection(),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          initialValue: _draft.categoryId,
          decoration: const InputDecoration(labelText: 'Danh mục'),
          items: [
            for (final c in _categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
          ],
          onChanged: (v) => setState(() => _draft.categoryId = v),
        ),
        const SizedBox(height: 16),
        Text('Độ khó', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: [
            for (final d in [1, 2, 3]) ButtonSegment(value: d, label: Text(difficultyLabel(d))),
          ],
          selected: {_draft.difficulty},
          onSelectionChanged: (s) => setState(() => _draft.difficulty = s.first),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _prep,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sơ chế (phút)'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _cook,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Nấu (phút)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Text('Khẩu phần gốc: ${_draft.baseServings} người', style: theme.textTheme.titleMedium)),
            IconButton.outlined(
              tooltip: 'Giảm khẩu phần',
              onPressed: _draft.baseServings > 1
                  ? () => setState(() => _draft.baseServings--)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Tăng khẩu phần',
              onPressed: _draft.baseServings < PostLimits.maxServings
                  ? () => setState(() => _draft.baseServings++)
                  : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('Nguyên liệu', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final ing in _draft.ingredients)
          _IngredientRow(
            key: ObjectKey(ing),
            draft: ing,
            onRemove: _draft.ingredients.length > 1
                ? () => setState(() => _draft.ingredients.remove(ing))
                : null,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _draft.ingredients.length < PostLimits.maxIngredients
                ? () => setState(() => _draft.ingredients.add(IngredientDraft()))
                : null,
            icon: const Icon(Icons.add),
            label: const Text('Thêm nguyên liệu'),
          ),
        ),
        const SizedBox(height: 16),
        Text('Các bước', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        for (var i = 0; i < _draft.steps.length; i++)
          _StepRow(
            key: ObjectKey(_draft.steps[i]),
            index: i,
            draft: _draft.steps[i],
            onUp: i > 0 ? () => setState(() => _swapSteps(i, i - 1)) : null,
            onDown: i < _draft.steps.length - 1
                ? () => setState(() => _swapSteps(i, i + 1))
                : null,
            onRemove: _draft.steps.length > 1
                ? () => setState(() => _draft.steps.removeAt(i))
                : null,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _draft.steps.length < PostLimits.maxSteps
                ? () => setState(() => _draft.steps.add(StepDraft()))
                : null,
            icon: const Icon(Icons.add),
            label: const Text('Thêm bước'),
          ),
        ),
      ],
    );
  }

  void _swapSteps(int a, int b) {
    final tmp = _draft.steps[a];
    _draft.steps[a] = _draft.steps[b];
    _draft.steps[b] = tmp;
  }

  Widget _imageSection() {
    return Row(
      children: [
        RecipeImage(size: 96, imageUrl: _draft.imageUrl),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                onPressed: _uploading || _busy ? null : _pickImage,
                icon: _uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.photo_library_outlined),
                label: Text(_draft.imageUrl == null ? 'Chọn ảnh' : 'Đổi ảnh'),
              ),
              if (_draft.imageUrl != null)
                TextButton(
                  onPressed: () => setState(() => _draft.imageUrl = null),
                  child: const Text('Bỏ ảnh'),
                ),
              const Text('JPG, PNG hoặc WebP, tối đa 3 MB (không bắt buộc)'),
            ],
          ),
        ),
      ],
    );
  }
}

class _IngredientRow extends StatefulWidget {
  const _IngredientRow({super.key, required this.draft, required this.onRemove});
  final IngredientDraft draft;
  final VoidCallback? onRemove;

  @override
  State<_IngredientRow> createState() => _IngredientRowState();
}

class _IngredientRowState extends State<_IngredientRow> {
  late final _name = TextEditingController(text: widget.draft.name);
  late final _quantity = TextEditingController(text: widget.draft.quantity);
  late final _unit = TextEditingController(text: widget.draft.unit);

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _unit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    onChanged: (v) => widget.draft.name = v,
                    decoration: const InputDecoration(labelText: 'Tên nguyên liệu'),
                  ),
                ),
                IconButton(
                  tooltip: 'Xóa nguyên liệu',
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    onChanged: (v) => widget.draft.quantity = v,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Số lượng'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _unit,
                    onChanged: (v) => widget.draft.unit = v,
                    decoration: const InputDecoration(labelText: 'Đơn vị (g, quả...)'),
                  ),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Tùy chọn'),
              value: widget.draft.isOptional,
              onChanged: (v) => setState(() => widget.draft.isOptional = v ?? false),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatefulWidget {
  const _StepRow({
    super.key,
    required this.index,
    required this.draft,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });

  final int index;
  final StepDraft draft;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onRemove;

  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  late final _text = TextEditingController(text: widget.draft.instruction);
  late final _timer = TextEditingController(
      text: widget.draft.timerMinutes == 0 ? '' : '${widget.draft.timerMinutes}');

  @override
  void dispose() {
    _text.dispose();
    _timer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(radius: 16, child: Text('${widget.index + 1}')),
                const Spacer(),
                IconButton(
                  tooltip: 'Đưa bước lên',
                  onPressed: widget.onUp,
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Đưa bước xuống',
                  onPressed: widget.onDown,
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: 'Xóa bước',
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            TextField(
              controller: _text,
              onChanged: (v) => widget.draft.instruction = v,
              maxLines: 3,
              maxLength: PostLimits.maxStepText,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nội dung bước'),
            ),
            TextField(
              controller: _timer,
              onChanged: (v) => widget.draft.timerMinutes = int.tryParse(v.trim()) ?? 0,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Hẹn giờ (phút, để trống nếu không cần)',
                prefixIcon: Icon(Icons.timer_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
