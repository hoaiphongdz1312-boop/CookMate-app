import 'package:cookmate/core/api_client.dart';
import 'package:cookmate/core/api_exception.dart';
import 'package:cookmate/core/services.dart';
import 'package:cookmate/core/token_storage.dart';
import 'package:cookmate/features/auth/auth_controller.dart';
import 'package:cookmate/features/lucky/lucky_meal_screen.dart';
import 'package:cookmate/features/recipes/recipe_models.dart';
import 'package:cookmate/features/recipes/recipe_repository.dart';
import 'package:cookmate/features/voice/voice_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = RecipeSummary(
    id: 1, name: 'Thịt kho trứng', description: '', imageUrl: null,
    difficulty: 2, prepMinutes: 20, cookMinutes: 60, categoryId: 1);
const _b = RecipeSummary(
    id: 3, name: 'Rau muống xào tỏi', description: '', imageUrl: null,
    difficulty: 1, prepMinutes: 10, cookMinutes: 5, categoryId: 2);

class _Repo implements RecipeRepository {
  final queue = <RecipeSummary>[_a, _b];
  final excludeHistory = <List<int>>[];
  int? lastDifficulty;

  @override
  Future<RecipeSummary> getRandom({
    int? categoryId,
    int? difficulty,
    int? maxMinutes,
    List<int> excludeIds = const [],
  }) async {
    excludeHistory.add(List.of(excludeIds));
    lastDifficulty = difficulty;
    if (queue.isEmpty) throw ApiException('Không có món', statusCode: 404);
    return queue.removeAt(0);
  }

  @override
  Future<List<Category>> getCategories() async => const [Category(id: 1, name: 'Món mặn')];

  @override
  Future<RecipePage> getRecipes({
    String? search,
    int? categoryId,
    int? difficulty,
    int? maxMinutes,
    int page = 1,
    int pageSize = 20,
  }) async =>
      RecipePage(items: const [_a, _b], page: 1, pageSize: pageSize, total: 2);

  @override
  Future<List<RecipeSummary>> getRecommended({int limit = 10}) async => const [];

  @override
  Future<RecipeDetail> getRecipe(int id) => throw UnimplementedError();
}

Widget _app(_Repo repo) {
  final tokens = TokenStorage();
  return Services(
    api: ApiClient(tokenStorage: tokens, onUnauthorized: () async {}),
    auth: AuthController(tokens),
    recipes: repo,
    voice: VoiceController(),
    child: const MaterialApp(
      home: LuckyMealScreen(spinDuration: Duration(milliseconds: 200)),
    ),
  );
}

void main() {
  testWidgets('quay dừng đúng món server trả, lần sau loại món đã trúng', (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('QUAY NGAY'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Đang chọn món...'), findsNothing); // đang chạy chữ quay, không phải trạng thái chờ
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Thịt kho trứng'), findsOneWidget);
    expect(find.text('Xem công thức'), findsOneWidget);
    expect(find.text('Nấu món này'), findsOneWidget);

    await tester.tap(find.text('THỬ MÓN KHÁC'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Rau muống xào tỏi'), findsOneWidget);
    expect(repo.excludeHistory, [[], [1]]);
  });

  testWidgets('hết món thì báo, không lỗi; quay lại từ đầu xóa danh sách loại', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo()..queue.removeLast();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('QUAY NGAY'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('THỬ MÓN KHÁC'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Bạn đã xem hết các món phù hợp.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    repo.queue.add(_b);
    await tester.tap(find.text('Quay lại từ đầu'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(repo.excludeHistory.last, isEmpty);
    expect(find.text('Rau muống xào tỏi'), findsOneWidget);
  });

  testWidgets('đổi bộ lọc thì gửi độ khó và xóa danh sách loại', (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('QUAY NGAY'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dễ'));
    await tester.pump();
    await tester.tap(find.text('QUAY NGAY'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(repo.lastDifficulty, 1);
    expect(repo.excludeHistory.last, isEmpty);
  });
}
