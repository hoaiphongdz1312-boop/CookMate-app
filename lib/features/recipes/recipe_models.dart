// Model đúng hợp đồng API, KE_HOACH_v2 mục 5 (Công thức).

class Category {
  const Category({required this.id, required this.name});

  final int id;
  final String name;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as int,
        name: json['name'] as String,
      );
}

/// Một phần tử trong `items` của GET /api/recipes
class RecipeSummary {
  const RecipeSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.difficulty,
    required this.prepMinutes,
    required this.cookMinutes,
    required this.categoryId,
    this.tastes = const [],
  });

  final int id;
  final String name;
  final String description;
  final String? imageUrl;
  final int difficulty;
  final int prepMinutes;
  final int cookMinutes;
  final int categoryId;
  final List<String> tastes;

  int get totalMinutes => prepMinutes + cookMinutes;

  factory RecipeSummary.fromJson(Map<String, dynamic> json) => RecipeSummary(
        id: json['id'] as int,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        difficulty: json['difficulty'] as int,
        prepMinutes: json['prepMinutes'] as int,
        cookMinutes: json['cookMinutes'] as int,
        categoryId: json['categoryId'] as int,
        tastes: (json['tastes'] as List<dynamic>? ?? []).cast<String>(),
      );
}

class Ingredient {
  const Ingredient({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.isOptional,
  });

  final int id;
  final String name;
  final double quantity;
  final String unit;
  final bool isOptional;

  factory Ingredient.fromJson(Map<String, dynamic> json) => Ingredient(
        id: json['id'] as int,
        name: json['name'] as String,
        // Server trả decimal, JSON có thể là 500 (int) hoặc 0.5 (double)
        quantity: (json['quantity'] as num).toDouble(),
        unit: json['unit'] as String,
        isOptional: json['isOptional'] as bool? ?? false,
      );
}

class RecipeStep {
  const RecipeStep({
    required this.stepNumber,
    required this.instruction,
    required this.timerSeconds,
  });

  final int stepNumber;
  final String instruction;

  /// 0 nếu bước không cần hẹn giờ
  final int timerSeconds;

  bool get hasTimer => timerSeconds > 0;

  factory RecipeStep.fromJson(Map<String, dynamic> json) => RecipeStep(
        stepNumber: json['stepNumber'] as int,
        instruction: json['instruction'] as String,
        timerSeconds: json['timerSeconds'] as int? ?? 0,
      );
}

/// GET /api/recipes/{id}
class RecipeDetail {
  const RecipeDetail({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.difficulty,
    required this.prepMinutes,
    required this.cookMinutes,
    required this.baseServings,
    required this.categoryId,
    required this.ingredients,
    required this.steps,
    this.authorId,
    this.authorName,
    this.status,
    this.rejectReason,
  });

  final int id;
  final String name;
  final String description;
  final String? imageUrl;
  final int difficulty;
  final int prepMinutes;
  final int cookMinutes;
  final int baseServings;
  final int categoryId;
  final List<Ingredient> ingredients;
  final List<RecipeStep> steps;

  /// Công thức do người dùng chia sẻ: có tác giả. Công thức hệ thống thì null.
  final int? authorId;
  final String? authorName;

  /// 0 chờ duyệt, 1 đã duyệt, 2 bị từ chối. Chỉ có khi người xem là tác giả hoặc admin.
  final int? status;
  final String? rejectReason;

  bool get isCommunity => authorId != null;

  int get totalMinutes => prepMinutes + cookMinutes;

  factory RecipeDetail.fromJson(Map<String, dynamic> json) => RecipeDetail(
        id: json['id'] as int,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        difficulty: json['difficulty'] as int,
        prepMinutes: json['prepMinutes'] as int,
        cookMinutes: json['cookMinutes'] as int,
        baseServings: json['baseServings'] as int,
        categoryId: json['categoryId'] as int,
        ingredients: (json['ingredients'] as List<dynamic>? ?? [])
            .map((e) => Ingredient.fromJson(e as Map<String, dynamic>))
            .toList(),
        steps: (json['steps'] as List<dynamic>? ?? [])
            .map((e) => RecipeStep.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.stepNumber.compareTo(b.stepNumber)),
        authorId: json['authorId'] as int?,
        authorName: json['authorName'] as String?,
        status: json['status'] as int?,
        rejectReason: json['rejectReason'] as String?,
      );
}

class RecipePage {
  const RecipePage({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<RecipeSummary> items;
  final int page;
  final int pageSize;
  final int total;

  factory RecipePage.fromJson(Map<String, dynamic> json) => RecipePage(
        items: (json['items'] as List<dynamic>)
            .map((e) => RecipeSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
        page: json['page'] as int,
        pageSize: json['pageSize'] as int,
        total: json['total'] as int,
      );
}

/// Nhãn hiển thị cho độ khó 1-3
String difficultyLabel(int difficulty) => switch (difficulty) {
      1 => 'Dễ',
      2 => 'Trung bình',
      3 => 'Khó',
      _ => 'Không rõ',
    };
