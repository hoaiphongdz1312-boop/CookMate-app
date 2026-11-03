import 'package:cookmate/core/api_client.dart';
import 'package:cookmate/core/api_exception.dart';
import 'package:cookmate/core/services.dart';
import 'package:cookmate/core/token_storage.dart';
import 'package:cookmate/features/auth/auth_controller.dart';
import 'package:cookmate/features/recipes/recipe_list_screen.dart';
import 'package:cookmate/features/recipes/recipe_models.dart';
import 'package:cookmate/features/recipes/recipe_repository.dart';
import 'package:cookmate/features/voice/voice_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements RecipeRepository {
  bool fail = false;
  List<RecipeSummary> recommended = const [];
  final searches = <String?>[];

  static const _all = [
    RecipeSummary(
        id: 1, name: 'Thịt kho trứng', description: '', imageUrl: null,
        difficulty: 2, prepMinutes: 20, cookMinutes: 60, categoryId: 1),
    RecipeSummary(
        id: 3, name: 'Rau muống xào tỏi', description: '', imageUrl: null,
        difficulty: 1, prepMinutes: 10, cookMinutes: 5, categoryId: 2),
  ];

  @override
  Future<List<Category>> getCategories() async =>
      const [Category(id: 1, name: 'Món mặn'), Category(id: 2, name: 'Rau')];

  @override
  Future<RecipePage> getRecipes({
    String? search,
    int? categoryId,
    int? difficulty,
    int? maxMinutes,
    int page = 1,
    int pageSize = 20,
  }) async {
    searches.add(search);
    if (fail) throw ApiException('Không kết nối được máy chủ.');
    final items = _all
        .where((r) => search == null || r.name.toLowerCase().contains(search.toLowerCase()))
        .where((r) => difficulty == null || r.difficulty == difficulty)
        .toList();
    return RecipePage(items: items, page: 1, pageSize: pageSize, total: items.length);
  }

  @override
  Future<List<RecipeSummary>> getRecommended({int limit = 10}) async => recommended;

  final picks = <int>[3, 1];
  final randomCalls = <List<int>>[];

  @override
  Future<RecipeSummary> getRandom({
    int? categoryId,
    int? difficulty,
    int? maxMinutes,
    List<int> excludeIds = const [],
  }) async {
    randomCalls.add(List.of(excludeIds));
    if (picks.isEmpty) throw ApiException('Không có món', statusCode: 404);
    return _all.firstWhere((r) => r.id == picks.removeAt(0));
  }

  @override
  Future<RecipeDetail> getRecipe(int id) => throw UnimplementedError();
}

Widget _app(_FakeRepo repo) {
  final tokens = TokenStorage();
  final auth = AuthController(tokens);
  return Services(
    api: ApiClient(tokenStorage: tokens, onUnauthorized: () async {}),
    auth: auth,
    recipes: repo,
    voice: VoiceController(),
    child: const MaterialApp(home: RecipeListScreen()),
  );
}

void main() {
  testWidgets('có gợi ý thì hiện mục Dành cho bạn, tìm kiếm thì ẩn đi', (tester) async {
    final repo = _FakeRepo()..recommended = [_FakeRepo._all[1]];
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    expect(find.text('Dành cho bạn'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'thịt');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Dành cho bạn'), findsNothing);
  });

  testWidgets('tìm kiếm chờ 400ms rồi mới gọi API', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    expect(find.text('Thịt kho trứng'), findsOneWidget);
    expect(find.text('Rau muống xào tỏi'), findsOneWidget);
    final callsBefore = repo.searches.length;

    await tester.enterText(find.byType(TextField), 'thịt kho');
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.searches.length, callsBefore, reason: 'chưa đủ 400ms');

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(repo.searches.length, callsBefore + 1);
    expect(find.text('Thịt kho trứng'), findsOneWidget);
    expect(find.text('Rau muống xào tỏi'), findsNothing);
  });

  testWidgets('lỗi mạng hiện nút Thử lại, bấm thì tải lại được', (tester) async {
    final repo = _FakeRepo()..fail = true;
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    expect(find.text('Không kết nối được máy chủ.'), findsOneWidget);

    repo.fail = false;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Thịt kho trứng'), findsOneWidget);
  });

  testWidgets('không có kết quả thì hiện trạng thái trống', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'phở');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Không có món nào phù hợp'), findsOneWidget);
  });
}
