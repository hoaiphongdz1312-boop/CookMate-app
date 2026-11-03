/// Quy đổi khẩu phần (KE_HOACH_v2 mục 5). Đây là NƠI DUY NHẤT tính lại định lượng.
///
/// quantity mới = quantity gốc × khẩu phần mới / baseServings.
/// Làm tròn: g → 5 g; thìa/chén → 1/4; còn lại 1 chữ số thập phân.
/// Khẩu phần cho phép 1–20.
const int minServings = 1;
const int maxServings = 20;

double scaleQuantity({
  required double quantity,
  required int baseServings,
  required int servings,
  required String unit,
}) {
  assert(baseServings >= 1);
  final raw = quantity * servings / baseServings;
  if (raw <= 0) return 0;

  final u = unit.trim().toLowerCase();
  final (step, decimals) = switch (u) {
    'g' || 'gam' || 'gram' => (5.0, 0),
    _ when u.startsWith('thìa') || u.startsWith('chén') => (0.25, 2),
    _ => (0.1, 1),
  };

  final rounded = (raw / step).round() * step;
  // Lượng rất nhỏ không được làm tròn về 0
  final result = rounded < step ? step : rounded;
  return double.parse(result.toStringAsFixed(decimals));
}

/// 500.0 → "500", 0.5 → "0,5", 0.25 → "0,25" (dấu phẩy kiểu Việt Nam).
String formatQuantity(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  return q.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceAll('.', ',');
}
