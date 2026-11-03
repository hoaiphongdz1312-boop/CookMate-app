import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/api_exception.dart';
import '../../core/services.dart';
import '../../core/widgets.dart';
import '../recipes/portion.dart';
import '../recipes/recipe_detail_screen.dart' show formatDuration;
import '../recipes/recipe_models.dart';
import '../recipes/step_instruction.dart';
import 'cooking_controller.dart';
import 'cooking_repository.dart';
import '../voice/voice_controller.dart';
import 'step_timer.dart';
import 'voice_command_parser.dart';
import 'voice_service.dart' show VoiceStatus;

/// Chế độ nấu: mỗi bước một màn, nút trước/sau, thanh tiến độ, hẹn giờ,
/// giữ màn hình sáng.
class CookingScreen extends StatefulWidget {
  const CookingScreen(
      {super.key, required this.recipeId, this.servings, this.voiceNext = false});

  final int recipeId;
  final int? servings;

  /// Mở bằng lệnh "bước tiếp theo" từ màn khác: tiếp tục bước đã lưu (không hỏi) rồi sang bước kế tiếp
  final bool voiceNext;

  @override
  State<CookingScreen> createState() => _CookingScreenState();
}

class _CookingScreenState extends State<CookingScreen> with WidgetsBindingObserver {
  RecipeDetail? _recipe;
  CookingController? _controller;
  String? _error;
  bool _loading = true;
  Timer? _ticker;
  final _alerted = <int>{};

  CookingRepository? _cooking;
  int? _sessionId;
  int _savedStep = 1; // bước cuối đã lưu thành công lên server
  bool _syncing = false;
  bool _finishing = false;

  // Điều khiển bằng giọng nói ("Bếp ơi, bước tiếp theo")
  late final VoiceController _voice;
  bool _voiceErrorShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _voice = Services.of(context).voice;
    _voice.commandHandler = _onVoiceCommand;
    _voice.addListener(_onVoiceChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    WakelockPlus.disable();
    _voice.removeListener(_onVoiceChanged);
    if (_voice.commandHandler == _onVoiceCommand) _voice.commandHandler = null;
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Quay lại app: kiểm tra ngay các bộ đếm đã hết giờ lúc ở nền
      _onTick();
    }
  }

  // Giọng nói đã ở cấp app; màn nấu chỉ báo lỗi micro và hiện trạng thái trên nút mic
  void _onVoiceChanged() {
    if (!mounted) return;
    if (_voice.status == VoiceStatus.unavailable) {
      final message = _voice.error;
      if (message != null && !_voiceErrorShown) {
        _voiceErrorShown = true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } else {
      _voiceErrorShown = false;
    }
    setState(() {});
  }

  void _onVoiceCommand(VoiceCommand command) {
    final c = _controller;
    if (c == null || !mounted) return;
    String message;
    switch (command) {
      case VoiceCommand.next:
        if (c.isLast) return; // không tự bấm Hoàn thành
        c.next();
        message = 'Đã chuyển sang bước ${c.stepNumber}';
      case VoiceCommand.previous:
        if (c.isFirst) return;
        c.previous();
        message = 'Đã quay lại bước ${c.stepNumber}';
      case VoiceCommand.startTimer:
        if (c.currentTimer == null) return;
        c.startTimer();
        message = 'Đã bắt đầu hẹn giờ';
      case VoiceCommand.pauseTimer:
        if (c.currentTimer == null) return;
        c.pauseTimer();
        message = 'Đã dừng hẹn giờ';
      case VoiceCommand.openCooking || VoiceCommand.goHome || VoiceCommand.luckyMeal:
        return; // VoiceController chuyển lệnh điều hướng cho cấp app
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 2), content: Text(message)));
  }

  Widget _micButton() {
    final scheme = Theme.of(context).colorScheme;
    final status = _voice.status;
    final armed = _voice.armed;
    final IconData icon;
    final Color? color;
    final String tooltip;
    switch (status) {
      case VoiceStatus.unavailable:
        icon = Icons.mic_off;
        color = scheme.error;
        tooltip = 'Giọng nói không dùng được. Chạm để thử lại';
      case VoiceStatus.starting:
        icon = Icons.mic_none;
        color = scheme.outline;
        tooltip = 'Đang bật giọng nói...';
      case VoiceStatus.listening:
        icon = Icons.mic;
        color = armed ? scheme.primary : scheme.outline;
        tooltip = armed ? 'Đã nghe "Bếp ơi", nói lệnh đi' : 'Đang nghe "Bếp ơi"';
      case VoiceStatus.off:
        icon = Icons.mic_none;
        color = null;
        tooltip = 'Bật điều khiển bằng giọng nói';
    }
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: color),
      style: armed && status == VoiceStatus.listening
          ? IconButton.styleFrom(backgroundColor: scheme.primaryContainer)
          : null,
      onPressed: status == VoiceStatus.starting ? null : _voice.toggle,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final services = Services.of(context);
      final recipe = await services.recipes.getRecipe(widget.recipeId);
      if (!mounted) return;
      var startStep = 1;
      if (recipe.steps.isNotEmpty) {
        _cooking ??= CookingRepository(services.api);
        // Lỗi mạng ở đây không chặn việc nấu: chỉ là không lưu được tiến độ
        try {
          final session =
              await _cooking!.start(recipe.id, widget.servings ?? recipe.baseServings);
          _sessionId = session.id;
          _savedStep = session.currentStep;
          if (session.currentStep > 1 && session.currentStep <= recipe.steps.length) {
            final resume = widget.voiceNext || await _askResume(session.currentStep);
            startStep = resume ? session.currentStep : 1;
          }
        } on ApiException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Chưa lưu được tiến độ: ${e.message}')));
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _recipe = recipe;
        _controller = recipe.steps.isEmpty
            ? null
            : CookingController(recipe.steps,
                startStep: startStep, onStepChanged: _pushStep);
        if (recipe.steps.isEmpty) _error = 'Món này chưa có các bước nấu';
      });
      // Chọn "Nấu lại": đưa bước đã lưu về 1
      if (startStep == 1 && _savedStep != 1) _pushStep(1);
      if (widget.voiceNext) _onVoiceCommand(VoiceCommand.next);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _askResume(int step) async {
    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Món đang nấu dở'),
        content: Text('Bạn đang ở bước $step. Tiếp tục hay nấu lại từ đầu?'),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Nấu lại')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            onPressed: () => context.pop(true),
            child: Text('Tiếp tục bước $step'),
          ),
        ],
      ),
    );
    return resume ?? true;
  }

  /// Lưu bước hiện tại lên server. Lỗi mạng thì giữ nguyên, lần đổi bước sau thử lại.
  Future<void> _pushStep(int step) async {
    final id = _sessionId;
    final repo = _cooking;
    if (id == null || repo == null || _syncing) return;
    _syncing = true;
    try {
      // Vòng lặp để bắt kịp nếu người dùng bấm tiếp trong lúc đang gửi
      while (true) {
        final target = _controller?.stepNumber ?? step;
        if (target == _savedStep) break;
        await repo.updateStep(id, target);
        _savedStep = target;
      }
    } on ApiException {
      // thử lại ở lần đổi bước kế tiếp hoặc khi hoàn thành
    } finally {
      _syncing = false;
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    final now = DateTime.now();
    for (final e in c.runningTimers) {
      if (e.value.isFinished(now) && _alerted.add(e.key)) _alertFinished(e.key);
    }
    // Hẹn lại hoặc đặt lại thì lần hết giờ sau được báo tiếp
    _alerted.removeWhere((i) => !(c.timerFor(i)?.isFinished(now) ?? false));
    c.tick();
  }

  void _alertFinished(int stepIndex) {
    _voice.muteFor(const Duration(seconds: 2));
    HapticFeedback.vibrate();
    SystemSound.play(SystemSoundType.alert);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Text('Hết giờ ở bước ${stepIndex + 1}!'),
    ));
  }

  void _showIngredients(RecipeDetail recipe) {
    final servings = widget.servings ?? recipe.baseServings;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text('Nguyên liệu cho $servings người',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final ing in recipe.ingredients)
              ListTile(
                title: Text(ing.name),
                trailing: Text(
                  '${formatQuantity(scaleQuantity(quantity: ing.quantity, baseServings: recipe.baseServings, servings: servings, unit: ing.unit))} ${ing.unit}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recipe = _recipe;
    final c = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(recipe?.name ?? 'Nấu ăn'),
        actions: [
          if (c != null) _micButton(),
          if (recipe != null)
            IconButton(
              tooltip: 'Xem nguyên liệu',
              icon: const Icon(Icons.list_alt),
              onPressed: () => _showIngredients(recipe),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || c == null
              ? ErrorView(message: _error ?? 'Có lỗi xảy ra', onRetry: _load)
              : ListenableBuilder(
                  listenable: c,
                  builder: (context, _) => _buildStep(context, c),
                ),
    );
  }

  Widget _buildStep(BuildContext context, CookingController c) {
    final theme = Theme.of(context);
    final timer = c.currentTimer;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              value: c.progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text('Bước ${c.stepNumber}/${c.total}', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: StepInstruction(text: c.current.instruction, large: true),
              ),
            ),
            if (timer != null) _TimerCard(controller: c, timer: timer),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: c.isFirst ? null : c.previous,
                    child: const Text('Trước'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _finishing ? null : (c.isLast ? _finish : c.next),
                    child: Text(c.isLast ? 'Hoàn thành' : 'Tiếp'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finish() async {
    if (_finishing) return;
    final id = _sessionId;
    final repo = _cooking;
    setState(() => _finishing = true);
    var saved = true;
    if (id != null && repo != null) {
      try {
        await repo.updateStep(id, _controller!.stepNumber);
        await repo.complete(id);
      } on ApiException catch (e) {
        saved = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Chưa lưu được kết quả: ${e.message}. Thử lại nhé.')));
        }
      }
    }
    if (!mounted) return;
    setState(() => _finishing = false);
    if (!saved) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.celebration, size: 48),
        title: const Text('Chúc mừng!'),
        content: Text('Bạn đã nấu xong ${_recipe?.name ?? 'món ăn'}.'),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            onPressed: () => context.pop(),
            child: const Text('Xong'),
          ),
        ],
      ),
    );
    if (mounted) context.pop();
  }
}

class _TimerCard extends StatelessWidget {
  const _TimerCard({required this.controller, required this.timer});

  final CookingController controller;
  final StepTimer timer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final left = timer.remaining(now);
    final finished = timer.isFinished(now);
    final mm = left.inMinutes.toString().padLeft(2, '0');
    final ss = (left.inSeconds % 60).toString().padLeft(2, '0');
    return Card(
      color: finished ? theme.colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.timer_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(finished ? 'Hết giờ!' : '$mm:$ss',
                      style: theme.textTheme.headlineMedium),
                  Text('Hẹn giờ ${formatDuration(timer.total.inSeconds)}',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (timer.isRunning && !finished)
              IconButton.filledTonal(
                tooltip: 'Tạm dừng',
                onPressed: controller.pauseTimer,
                icon: const Icon(Icons.pause),
              )
            else
              IconButton.filled(
                tooltip: finished ? 'Hẹn lại' : 'Bắt đầu',
                onPressed: controller.startTimer,
                icon: const Icon(Icons.play_arrow),
              ),
            IconButton(
              tooltip: 'Đặt lại',
              onPressed: timer.isIdle ? null : controller.resetTimer,
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ),
      ),
    );
  }
}
