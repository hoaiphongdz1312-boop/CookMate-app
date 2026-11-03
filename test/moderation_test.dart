import 'package:cookmate/features/community/community_models.dart';
import 'package:cookmate/features/community/moderation_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parse', () {
    test('ReportReason khớp mã server, mã lạ thành Khác', () {
      expect(ReportReason.values.map((r) => r.code),
          ['wrong_info', 'spam', 'offensive', 'copyright', 'other']);
      expect(ReportReason.fromCode('spam'), ReportReason.spam);
      expect(ReportReason.fromCode('khong-ro'), ReportReason.other);
    });

    test('ReportedRecipe đọc danh sách báo cáo, công thức hệ thống không có tác giả', () {
      final r = ReportedRecipe.fromJson({
        'recipeId': 7,
        'name': 'Phở gà',
        'imageUrl': null,
        'authorId': null,
        'authorName': null,
        'reportCount': 2,
        'latestReportAt': '2026-11-02T03:00:00',
        'reports': [
          {
            'id': 1,
            'reason': 'wrong_info',
            'detail': 'Sai lượng muối',
            'reporterName': 'An',
            'createdAt': '2026-11-02T03:00:00',
          },
        ],
      });
      expect(r.authorName, isNull);
      expect(r.reportCount, 2);
      expect(r.reports.single.reason, ReportReason.wrongInfo);
      expect(r.reports.single.detail, 'Sai lượng muối');
    });

    test('AppNotification phân biệt duyệt và từ chối/gỡ', () {
      AppNotification parse(String type) => AppNotification.fromJson({
            'id': 1,
            'type': type,
            'recipeId': 3,
            'title': 't',
            'body': 'b',
            'isRead': false,
            'createdAt': '2026-11-02T03:00:00Z',
          });
      expect(parse('post_approved').isPositive, isTrue);
      expect(parse('post_rejected').isPositive, isFalse);
      expect(parse('post_removed').isPositive, isFalse);
    });

    test('Thông báo sau khi đăng theo trạng thái', () {
      expect(createdMessage(PostStatus.approved), contains('Đã đăng'));
      expect(createdMessage(PostStatus.pending), contains('chờ duyệt'));
    });
  });

  group('ReportDialog', () {
    Future<(ReportReason, String)?> open(WidgetTester tester) async {
      (ReportReason, String)? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showDialog<(ReportReason, String)>(
              context: context,
              builder: (_) => const ReportDialog(),
            ),
            child: const Text('mở'),
          ),
        ),
      ));
      await tester.tap(find.text('mở'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('bắt chọn lý do, lý do Khác bắt mô tả', (tester) async {
      await open(tester);
      await tester.tap(find.text('Gửi báo cáo'));
      await tester.pump();
      expect(find.text('Vui lòng chọn lý do'), findsOneWidget);

      await tester.tap(find.text('Khác'));
      await tester.pump();
      await tester.tap(find.text('Gửi báo cáo'));
      await tester.pump();
      expect(find.text('Vui lòng mô tả vi phạm'), findsOneWidget);
      expect(find.byType(ReportDialog), findsOneWidget);
    });

    testWidgets('chọn Spam rồi gửi thì đóng hộp thoại', (tester) async {
      await open(tester);
      await tester.tap(find.text('Spam, quảng cáo'));
      await tester.pump();
      await tester.tap(find.text('Gửi báo cáo'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportDialog), findsNothing);
    });
  });
}
