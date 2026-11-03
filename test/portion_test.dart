import 'package:cookmate/features/recipes/portion.dart';
import 'package:flutter_test/flutter_test.dart';

double _scale(double q, int base, int servings, String unit) =>
    scaleQuantity(quantity: q, baseServings: base, servings: servings, unit: unit);

void main() {
  test('2 người lên 4 người: nhân đôi', () {
    expect(_scale(300, 2, 4, 'g'), 600);
    expect(_scale(2, 2, 4, 'quả'), 4);
    expect(_scale(1, 2, 4, 'thìa canh'), 2);
  });

  test('số lẻ như 3 người', () {
    expect(_scale(1, 2, 3, 'thìa canh'), 1.5);
    expect(_scale(1, 2, 3, 'quả'), 1.5);
    expect(_scale(1, 4, 3, 'thìa cà phê'), 0.75);
  });

  test('gram làm tròn 5 g', () {
    expect(_scale(250, 2, 3, 'g'), 375);
    expect(_scale(100, 3, 4, 'g'), 135); // 133,33 → 135
    expect(_scale(100, 3, 1, 'g'), 35); // 33,33 → 35
  });

  test('thìa/chén làm tròn 1/4', () {
    expect(_scale(1, 3, 1, 'thìa canh'), 0.25); // 0,333 → 0,25
    expect(_scale(1, 3, 2, 'thìa cà phê'), 0.75); // 0,667 → 0,75
    expect(_scale(1, 2, 3, 'chén'), 1.5);
  });

  test('đơn vị khác làm tròn 1 chữ số thập phân', () {
    expect(_scale(1, 3, 1, 'củ'), 0.3);
    expect(_scale(100, 3, 4, 'ml'), 133.3);
  });

  test('lượng nhỏ không bị làm tròn về 0', () {
    expect(_scale(2, 4, 1, 'g'), 5);
    expect(_scale(0.5, 20, 1, 'quả'), 0.1);
  });

  test('giữ nguyên khi khẩu phần bằng gốc', () {
    expect(_scale(300, 2, 2, 'g'), 300);
    expect(_scale(1.5, 2, 2, 'thìa canh'), 1.5);
  });

  test('formatQuantity', () {
    expect(formatQuantity(500), '500');
    expect(formatQuantity(0.5), '0,5');
    expect(formatQuantity(0.25), '0,25');
    expect(formatQuantity(1.5), '1,5');
  });
}
