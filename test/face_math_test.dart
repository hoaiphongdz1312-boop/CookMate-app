import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cookmate/face/face_math.dart';

double _norm(List<double> v) => math.sqrt(v.fold(0.0, (s, x) => s + x * x));

void main() {
  group('l2Normalize', () {
    test('vector kết quả có độ dài 1 và giữ hướng', () {
      final n = l2Normalize([3, 4]);
      expect(n[0], closeTo(0.6, 1e-6));
      expect(n[1], closeTo(0.8, 1e-6));
      expect(_norm(n), closeTo(1, 1e-6));
    });

    test('vector 0 không gây chia cho 0', () {
      final n = l2Normalize([0, 0, 0]);
      expect(n, everyElement(0));
    });

    test('vector đã chuẩn hóa thì giữ nguyên', () {
      final n = l2Normalize(l2Normalize([1, 2, 3]));
      final m = l2Normalize([1, 2, 3]);
      for (var i = 0; i < 3; i++) {
        expect(n[i], closeTo(m[i], 1e-6));
      }
    });
  });

  group('cosineSimilarity', () {
    test('cùng hướng = 1, không phụ thuộc độ dài', () {
      expect(cosineSimilarity([1, 2, 3], [2, 4, 6]), closeTo(1, 1e-9));
    });

    test('vuông góc = 0, ngược hướng = -1', () {
      expect(cosineSimilarity([1, 0], [0, 1]), closeTo(0, 1e-9));
      expect(cosineSimilarity([1, 2], [-1, -2]), closeTo(-1, 1e-9));
    });

    test('vector 0 cho kết quả 0', () {
      expect(cosineSimilarity([0, 0], [1, 1]), 0);
    });

    test('khác số chiều thì báo lỗi', () {
      expect(() => cosineSimilarity([1, 2], [1, 2, 3]), throwsArgumentError);
    });
  });

  group('averageEmbedding', () {
    test('mỗi mẫu đóng góp như nhau dù độ dài khác nhau', () {
      final avg = averageEmbedding([
        [10, 0],
        [0, 1],
      ]);
      expect(avg[0], closeTo(avg[1], 1e-6));
      expect(_norm(avg), closeTo(1, 1e-6));
    });

    test('danh sách rỗng thì báo lỗi', () {
      expect(() => averageEmbedding([]), throwsArgumentError);
    });
  });

  group('findBestMatch', () {
    final people = {
      'An': [1.0, 0.0, 0.0],
      'Bình': [0.0, 1.0, 0.0],
      'Chi': [0.7, 0.7, 0.0],
    };
    List<double> emb(String name) => people[name]!;

    test('chọn người giống nhất và chấp nhận khi đạt ngưỡng', () {
      final r = findBestMatch([0.9, 0.1, 0.0], people.keys, emb, threshold: 0.7);
      expect(r, isNotNull);
      expect(r!.candidate, 'An');
      expect(r.accepted, isTrue);
    });

    test('vẫn trả người giống nhất nhưng từ chối khi dưới ngưỡng', () {
      final r = findBestMatch([0.0, 0.0, 1.0], people.keys, emb, threshold: 0.7);
      expect(r, isNotNull);
      expect(r!.accepted, isFalse);
      expect(r.score, lessThan(0.7));
    });

    test('đúng bằng ngưỡng thì chấp nhận', () {
      final r = findBestMatch([1.0, 0.0, 0.0], ['An'], emb, threshold: 1.0);
      expect(r!.accepted, isTrue);
    });

    test('không có ứng viên thì trả null', () {
      expect(findBestMatch([1.0], <String>[], emb, threshold: 0.5), isNull);
    });

    test('ghi lại độ giống của người thứ hai', () {
      final r = findBestMatch([0.9, 0.1, 0.0], people.keys, emb, threshold: 0.7);
      // Thứ hai là Chi (cos ≈ 0.78), không phải Bình.
      expect(r!.secondScore, closeTo(0.78, 0.01));
    });

    test('đạt ngưỡng nhưng không bỏ xa người thứ hai thì từ chối', () {
      // An ≈ 0.99, Chi ≈ 0.78 → cách nhau ≈ 0.21.
      final q = [0.9, 0.1, 0.0];
      expect(
        findBestMatch(q, people.keys, emb, threshold: 0.7, margin: 0.3)!.accepted,
        isFalse,
      );
      expect(
        findBestMatch(q, people.keys, emb, threshold: 0.7, margin: 0.1)!.accepted,
        isTrue,
      );
    });

    test('hai người giống xấp xỉ nhau thì không chọn ai', () {
      // Nằm giữa An và Chi: giống cả hai gần như nhau.
      final r = findBestMatch([0.95, 0.35, 0.0], ['An', 'Chi'], emb,
          threshold: 0.7, margin: 0.08);
      expect(r!.score, greaterThan(0.7));
      expect(r.accepted, isFalse);
    });

    test('chỉ một ứng viên thì không xét khoảng cách', () {
      final r = findBestMatch([1.0, 0.0, 0.0], ['An'], emb,
          threshold: 0.9, margin: 0.5);
      expect(r!.secondScore, isNull);
      expect(r.accepted, isTrue);
    });
  });

  group('ConsecutiveMatchCounter', () {
    test('đủ số khung liên tiếp cùng người thì đạt', () {
      final c = ConsecutiveMatchCounter<int>(3);
      expect(c.add(1), isFalse);
      expect(c.add(1), isFalse);
      expect(c.add(1), isTrue);
    });

    test('đổi người giữa chừng thì đếm lại', () {
      final c = ConsecutiveMatchCounter<int>(3);
      c.add(1);
      c.add(1);
      expect(c.add(2), isFalse);
      expect(c.count, 1);
      c.add(2);
      expect(c.add(2), isTrue);
    });

    test('một khung không khớp làm mất chuỗi', () {
      final c = ConsecutiveMatchCounter<int>(2);
      c.add(1);
      expect(c.add(null), isFalse);
      expect(c.count, 0);
      expect(c.add(1), isFalse);
      expect(c.add(1), isTrue);
    });
  });

  group('isConsistentSample', () {
    test('mẫu đầu tiên luôn hợp lệ', () {
      expect(isConsistentSample([1, 0, 0], [], minSimilarity: 0.9), isTrue);
    });

    test('mẫu gần giống các mẫu trước thì nhận', () {
      final prev = [
        [1.0, 0.1, 0.0],
        [1.0, -0.1, 0.0],
      ];
      expect(isConsistentSample([1.0, 0.05, 0.0], prev, minSimilarity: 0.9),
          isTrue);
    });

    test('mẫu của người khác thì loại', () {
      final prev = [
        [1.0, 0.0, 0.0],
        [0.95, 0.05, 0.0],
      ];
      expect(isConsistentSample([0.0, 1.0, 0.0], prev, minSimilarity: 0.75),
          isFalse);
    });
  });
}
