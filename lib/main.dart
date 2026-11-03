import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/api_client.dart';
import 'core/api_exception.dart';
import 'core/services.dart';
import 'core/token_storage.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/auth_repository.dart';
import 'features/cooking/cooking_repository.dart';
import 'features/cooking/voice_command_parser.dart';
import 'features/recipes/recipe_repository.dart';
import 'features/voice/voice_controller.dart';
import 'features/voice/voice_overlay.dart';
import 'router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final tokenStorage = TokenStorage();
  final auth = AuthController(tokenStorage);
  final api = ApiClient(tokenStorage: tokenStorage, onUnauthorized: auth.onUnauthorized);
  auth.attach(AuthRepository(api));

  final recipes = ApiRecipeRepository(api);

  final voice = VoiceController();

  runApp(CookMateApp(api: api, auth: auth, recipes: recipes, voice: voice));
  auth.restore();
}

class CookMateApp extends StatefulWidget {
  const CookMateApp({
    super.key,
    required this.api,
    required this.auth,
    required this.recipes,
    required this.voice,
  });

  final ApiClient api;
  final AuthController auth;
  final RecipeRepository recipes;
  final VoiceController voice;

  @override
  State<CookMateApp> createState() => _CookMateAppState();
}

class _CookMateAppState extends State<CookMateApp> {
  late final GoRouter _router = createRouter(widget.auth);

  @override
  void initState() {
    super.initState();
    widget.auth.addListener(_onAuthChanged);
    widget.voice.navigationHandler = _onNavigationCommand;
  }

  String get _path => _router.routerDelegate.currentConfiguration.uri.path;

  // Lệnh điều hướng bằng giọng nói, dùng được ở mọi màn
  Future<void> _onNavigationCommand(VoiceCommand command) async {
    final voice = widget.voice;
    switch (command) {
      case VoiceCommand.goHome:
        _router.go('/');
      case VoiceCommand.luckyMeal:
        if (_path != '/lucky') _router.push('/lucky');
      case VoiceCommand.openCooking:
        if (_path.endsWith('/cook')) {
          voice.showNotice('Bạn đang ở màn nấu rồi');
          return;
        }
        await _openInProgress();
      case VoiceCommand.next:
        // Chỉ tới đây khi chưa ở màn nấu: mở món đang nấu dở và sang bước kế tiếp
        await _openInProgress(query: '?voice=next');
      case VoiceCommand.previous ||
            VoiceCommand.startTimer ||
            VoiceCommand.pauseTimer:
        break; // lệnh nấu ăn do màn nấu xử lý
    }
  }

  // Mở màn nấu của món đang nấu dở gần nhất
  Future<void> _openInProgress({String query = ''}) async {
    final voice = widget.voice;
    try {
      final progress = await CookingRepository(widget.api).progress();
      if (progress.inProgress.isEmpty) {
        voice.showNotice('Bạn chưa có món nào đang nấu dở');
      } else {
        _router.push('/recipes/${progress.inProgress.first.recipeId}/cook$query');
      }
    } on ApiException catch (e) {
      voice.showNotice(e.message);
    }
  }

  // Đăng xuất thì tắt nghe: micro không được mở khi chưa đăng nhập
  void _onAuthChanged() {
    if (widget.auth.status == AuthStatus.unauthenticated) widget.voice.disable();
  }

  @override
  void dispose() {
    widget.auth.removeListener(_onAuthChanged);
    widget.voice.navigationHandler = null;
    widget.voice.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Services(
      api: widget.api,
      auth: widget.auth,
      recipes: widget.recipes,
      voice: widget.voice,
      child: MaterialApp.router(
        title: 'CookMate',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        routerConfig: _router,
        // Bảng "Bạn cần gì?" nằm trên mọi màn hình
        builder: (context, child) => VoiceOverlay(voice: widget.voice, child: child!),
      ),
    );
  }
}

/// Material 3, chữ to hơn mặc định để đọc được khi đứng cách máy lúc nấu.
ThemeData buildTheme(Brightness brightness) {
  final base = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFFE07A2E),
    brightness: brightness,
  );
  final t = base.textTheme;
  return base.copyWith(
    textTheme: t.copyWith(
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 18, height: 1.4),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 16, height: 1.35),
      titleMedium: t.titleMedium?.copyWith(fontSize: 18),
      titleLarge: t.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
      labelLarge: t.labelLarge?.copyWith(fontSize: 15),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 17),
      ),
    ),
  );
}
