import 'package:cookmate/features/auth/app_user.dart';
import 'package:cookmate/features/community/community_models.dart';
import 'package:cookmate/features/home/main_shell.dart';
import 'package:cookmate/features/recipes/recipe_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

PostDraft _valid() => PostDraft(
      name: 'Trứng chiên',
      description: 'Món nhanh',
      categoryId: 1,
      ingredients: [IngredientDraft(name: 'Trứng', quantity: '2', unit: 'quả')],
      steps: [StepDraft(instruction: 'Chiên trứng', timerMinutes: 2)],
    );

void main() {
  group('parse', () {
    test('MyPost đủ 3 trạng thái, rejectReason null hoặc có', () {
      MyPost parse(int status, String? reason) => MyPost.fromJson({
            'id': 1,
            'name': 'Món',
            'description': 'd',
            'imageUrl': null,
            'status': status,
            'rejectReason': reason,
            'submittedAt': '2026-10-31T01:00:00',
          });

      expect(parse(0, null).status, PostStatus.pending);
      expect(parse(1, null).status, PostStatus.approved);
      final rejected = parse(2, 'Thiếu bước');
      expect(rejected.status, PostStatus.rejected);
      expect(rejected.rejectReason, 'Thiếu bước');
      expect(rejected.submittedAt, isNotNull);
      expect(() => parse(9, null), throwsFormatException);
    });

    test('CommunityPost đọc tác giả và ảnh', () {
      final p = CommunityPost.fromJson({
        'id': 5,
        'name': 'Canh chua',
        'description': 'Ngon',
        'imageUrl': '/uploads/a.jpg',
        'difficulty': 2,
        'prepMinutes': 10,
        'cookMinutes': 20,
        'categoryId': 3,
        'authorName': 'Lan',
        'publishedAt': '2026-10-31T01:00:00Z',
      });
      expect(p.authorName, 'Lan');
      expect(p.totalMinutes, 30);
      expect(p.imageUrl, '/uploads/a.jpg');
    });

    test('RecipeDetail đọc tác giả, status; công thức hệ thống không có tác giả', () {
      Map<String, dynamic> json(Map<String, dynamic> extra) => {
            'id': 1,
            'name': 'Món',
            'description': 'd',
            'difficulty': 1,
            'prepMinutes': 1,
            'cookMinutes': 1,
            'baseServings': 2,
            'categoryId': 1,
            'ingredients': [],
            'steps': [],
            ...extra,
          };
      final system = RecipeDetail.fromJson(json({}));
      expect(system.isCommunity, isFalse);
      expect(system.status, isNull);
      final mine = RecipeDetail.fromJson(
          json({'authorId': 7, 'authorName': 'Lan', 'status': 2, 'rejectReason': 'x'}));
      expect(mine.isCommunity, isTrue);
      expect(mine.status, 2);
      expect(mine.rejectReason, 'x');
    });

    test('AppUser.isAdmin theo role, thiếu role thì là User', () {
      AppUser user(Map<String, dynamic> extra) => AppUser.fromJson({
            'id': 1,
            'email': 'a@b.vn',
            'fullName': 'A',
            'hasFace': false,
            ...extra,
          });
      expect(user({'role': 'Admin'}).isAdmin, isTrue);
      expect(user({'role': 'User'}).isAdmin, isFalse);
      expect(user({}).isAdmin, isFalse);
    });
  });

  group('validate form', () {
    test('bản nháp hợp lệ', () => expect(_valid().validate(), isNull));

    test('thiếu tên, danh mục, nguyên liệu, bước', () {
      expect((_valid()..name = ' ').validate(), contains('tên'));
      expect((_valid()..categoryId = null).validate(), contains('danh mục'));
      expect((_valid()..ingredients = []).validate(), contains('nguyên liệu'));
      expect((_valid()..steps = []).validate(), contains('bước'));
    });

    test('số âm hoặc không phải số', () {
      expect((_valid()..prepMinutes = -1).validate(), contains('âm'));
      final negative = _valid()..ingredients = [IngredientDraft(name: 'Muối', quantity: '-1', unit: 'g')];
      expect(negative.validate(), contains('âm'));
      final notNumber = _valid()..ingredients = [IngredientDraft(name: 'Muối', quantity: 'abc', unit: 'g')];
      expect(notNumber.validate(), contains('không hợp lệ'));
      expect((_valid()..steps = [StepDraft(instruction: 'x', timerMinutes: 1441)]).validate(),
          contains('hẹn giờ'));
    });

    test('quá giới hạn số lượng', () {
      final tooManyIngredients = _valid()
        ..ingredients = List.generate(41, (i) => IngredientDraft(name: 'N$i', quantity: '1', unit: 'g'));
      expect(tooManyIngredients.validate(), contains('40'));
      final tooManySteps = _valid()
        ..steps = List.generate(31, (i) => StepDraft(instruction: 'B$i'));
      expect(tooManySteps.validate(), contains('30'));
    });

    test('toJson đổi phút thành giây và dấu phẩy thập phân', () {
      final d = _valid()
        ..ingredients = [IngredientDraft(name: 'Đường', quantity: '0,5', unit: 'kg')];
      final json = d.toJson();
      expect((json['steps'] as List).first['timerSeconds'], 120);
      expect((json['ingredients'] as List).first['quantity'], 0.5);
    });
  });

  test('timeAgo', () {
    final now = DateTime(2026, 10, 31, 12);
    expect(timeAgo(now.subtract(const Duration(seconds: 10)), now: now), 'vừa xong');
    expect(timeAgo(now.subtract(const Duration(minutes: 5)), now: now), '5 phút trước');
    expect(timeAgo(now.subtract(const Duration(hours: 3)), now: now), '3 giờ trước');
    expect(timeAgo(now.subtract(const Duration(days: 2)), now: now), '2 ngày trước');
  });

  testWidgets('MainShell có 3 tab, tab Cộng đồng ở vị trí thứ 2', (tester) async {
    final router = GoRouter(
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => MainShell(shell: shell),
          branches: [
            for (final path in ['/', '/community', '/profile'])
              StatefulShellBranch(routes: [
                GoRoute(path: path, builder: (_, _) => Text('màn $path')),
              ]),
          ],
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(find.text('Cộng đồng'), findsOneWidget);

    await tester.tap(find.text('Cộng đồng'));
    await tester.pumpAndSettle();
    expect(find.text('màn /community'), findsOneWidget);
  });
}
