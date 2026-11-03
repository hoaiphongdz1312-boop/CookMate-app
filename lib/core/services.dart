import 'package:flutter/widgets.dart';

import '../features/auth/auth_controller.dart';
import '../features/recipes/recipe_repository.dart';
import '../features/voice/voice_controller.dart';
import 'api_client.dart';

/// Các service dùng chung, tạo một lần trong main() và truyền xuống cây widget.
class Services extends InheritedWidget {
  const Services({
    super.key,
    required this.api,
    required this.auth,
    required this.recipes,
    required this.voice,
    required super.child,
  });

  final ApiClient api;
  final AuthController auth;
  final RecipeRepository recipes;
  final VoiceController voice;

  static Services of(BuildContext context) {
    final services = context.getInheritedWidgetOfExactType<Services>();
    assert(services != null, 'Không tìm thấy Services trong cây widget');
    return services!;
  }

  @override
  bool updateShouldNotify(Services oldWidget) => false;
}
