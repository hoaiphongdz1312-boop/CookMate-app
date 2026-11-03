import '../../core/api_client.dart';
import 'recipe_models.dart';

/// Nguồn dữ liệu công thức. Màn hình chỉ biết interface này.
abstract interface class RecipeRepository {
  Future<List<Category>> getCategories();

  Future<RecipePage> getRecipes({
    String? search,
    int? categoryId,
    int? difficulty,
    int? maxMinutes,
    int page = 1,
    int pageSize = 20,
  });

  /// Món hệ thống xếp theo khẩu vị của người đăng nhập
  Future<List<RecipeSummary>> getRecommended({int limit = 10});

  /// Quay ngẫu nhiên một món hệ thống. Không có món phù hợp thì ném ApiException (404).
  Future<RecipeSummary> getRandom({
    int? categoryId,
    int? difficulty,
    int? maxMinutes,
    List<int> excludeIds = const [],
  });

  Future<RecipeDetail> getRecipe(int id);
}

/// Cài đặt gọi API thật qua ApiClient dùng chung (bước F4).
class ApiRecipeRepository implements RecipeRepository {
  ApiRecipeRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<Category>> getCategories() async {
    final json = await _api.get<List<dynamic>>('/categories');
    return json.map((e) => Category.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<RecipePage> getRecipes({
    String? search,
    int? categoryId,
    int? difficulty,
    int? maxMinutes,
    int page = 1,
    int pageSize = 20,
  }) async {
    final json = await _api.get<Map<String, dynamic>>('/recipes', query: {
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      'categoryId': ?categoryId,
      'difficulty': ?difficulty,
      'maxMinutes': ?maxMinutes,
      'page': page,
      'pageSize': pageSize,
    });
    return RecipePage.fromJson(json);
  }

  @override
  Future<List<RecipeSummary>> getRecommended({int limit = 10}) async {
    final json = await _api.get<List<dynamic>>('/recipes/recommended', query: {'limit': limit});
    return json.map((e) => RecipeSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<RecipeSummary> getRandom({
    int? categoryId,
    int? difficulty,
    int? maxMinutes,
    List<int> excludeIds = const [],
  }) async {
    final json = await _api.get<Map<String, dynamic>>('/recipes/random', query: {
      'categoryId': ?categoryId,
      'difficulty': ?difficulty,
      'maxMinutes': ?maxMinutes,
      if (excludeIds.isNotEmpty) 'excludeIds': excludeIds,
    });
    return RecipeSummary.fromJson(json);
  }

  @override
  Future<RecipeDetail> getRecipe(int id) async {
    final json = await _api.get<Map<String, dynamic>>('/recipes/$id');
    return RecipeDetail.fromJson(json);
  }
}
