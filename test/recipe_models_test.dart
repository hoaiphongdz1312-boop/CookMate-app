import 'package:cookmate/features/recipes/recipe_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RecipeDetail.fromJson đọc đúng hợp đồng và sắp bước theo stepNumber', () {
    final r = RecipeDetail.fromJson({
      'id': 1,
      'name': 'Thịt kho trứng',
      'description': 'mô tả',
      'imageUrl': null,
      'difficulty': 2,
      'prepMinutes': 20,
      'cookMinutes': 60,
      'baseServings': 4,
      'categoryId': 1,
      'ingredients': [
        {'id': 1, 'name': 'Thịt', 'quantity': 500, 'unit': 'g', 'isOptional': false},
        {'id': 2, 'name': 'Hạt nêm', 'quantity': 0.5, 'unit': 'thìa cà phê', 'isOptional': true},
      ],
      'steps': [
        {'stepNumber': 2, 'instruction': 'B', 'timerSeconds': 0},
        {'stepNumber': 1, 'instruction': 'A', 'timerSeconds': 600},
      ],
    });

    expect(r.totalMinutes, 80);
    expect(r.imageUrl, isNull);
    expect(r.ingredients[0].quantity, 500.0);
    expect(r.ingredients[1].quantity, 0.5);
    expect(r.ingredients[1].isOptional, isTrue);
    expect(r.steps.map((s) => s.stepNumber), [1, 2]);
    expect(r.steps.first.hasTimer, isTrue);
  });

  test('RecipePage.fromJson', () {
    final p = RecipePage.fromJson({
      'items': [
        {
          'id': 3,
          'name': 'Rau muống xào tỏi',
          'description': '',
          'imageUrl': null,
          'difficulty': 1,
          'prepMinutes': 10,
          'cookMinutes': 5,
          'categoryId': 3,
        }
      ],
      'page': 1,
      'pageSize': 20,
      'total': 1,
    });
    expect(p.items.single.name, 'Rau muống xào tỏi');
    expect(p.total, 1);
  });
}
