import 'dart:math' as math;
import 'dart:typed_data';

/// Các hàm thuần cho vector embedding khuôn mặt (không phụ thuộc Flutter,
/// test được trên máy tính).

/// Chuẩn hóa L2: trả về vector cùng hướng có độ dài 1.
/// Vector toàn 0 được trả về nguyên trạng (không chia cho 0).
Float32List l2Normalize(List<double> v) {
  var sumSq = 0.0;
  for (final x in v) {
    sumSq += x * x;
  }
  final out = Float32List(v.length);
  if (sumSq == 0) return out;
  final inv = 1 / math.sqrt(sumSq);
  for (var i = 0; i < v.length; i++) {
    out[i] = v[i] * inv;
  }
  return out;
}

/// Độ giống cosine trong khoảng [-1, 1].
/// Không giả định đầu vào đã chuẩn hóa. Trả về 0 nếu một vector toàn 0.
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) {
    throw ArgumentError('Khác số chiều: ${a.length} và ${b.length}');
  }
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

/// Vector đại diện khi đăng ký: chuẩn hóa từng mẫu, lấy trung bình,
/// rồi chuẩn hóa lại (để mỗi mẫu đóng góp như nhau).
Float32List averageEmbedding(List<List<double>> samples) {
  if (samples.isEmpty) throw ArgumentError('Cần ít nhất 1 mẫu');
  final dim = samples.first.length;
  final sum = Float64List(dim);
  for (final s in samples) {
    if (s.length != dim) throw ArgumentError('Các mẫu khác số chiều');
    final n = l2Normalize(s);
    for (var i = 0; i < dim; i++) {
      sum[i] += n[i];
    }
  }
  return l2Normalize(sum);
}

/// Kết quả so khớp: ứng viên giống nhất và độ giống của nó.
class MatchResult<T> {
  const MatchResult(
    this.candidate,
    this.score, {
    required this.accepted,
    this.secondScore,
  });

  final T candidate;
  final double score;

  /// Độ giống của ứng viên đứng thứ hai (`null` nếu chỉ có 1 ứng viên).
  final double? secondScore;

  /// `true` nếu [score] đạt ngưỡng VÀ bỏ xa ứng viên thứ hai đủ khoảng cách.
  final bool accepted;
}

/// Tìm ứng viên có độ giống cosine cao nhất với [query].
///
/// Chỉ chấp nhận khi:
/// - độ giống ≥ [threshold], và
/// - hơn ứng viên thứ hai ít nhất [margin] (khi có từ 2 ứng viên) — nếu hai
///   người cùng giống xấp xỉ nhau thì không đủ chắc để chọn ai.
///
/// Luôn trả về ứng viên tốt nhất (để ghi debug log), kèm cờ [MatchResult.accepted].
/// Trả về `null` khi không có ứng viên.
MatchResult<T>? findBestMatch<T>(
  List<double> query,
  Iterable<T> candidates,
  List<double> Function(T) embeddingOf, {
  required double threshold,
  double margin = 0,
}) {
  T? best;
  var bestScore = double.negativeInfinity;
  double? secondScore;
  for (final c in candidates) {
    final score = cosineSimilarity(query, embeddingOf(c));
    if (best == null || score > bestScore) {
      if (best != null) secondScore = bestScore;
      best = c;
      bestScore = score;
    } else if (secondScore == null || score > secondScore) {
      secondScore = score;
    }
  }
  if (best == null) return null;
  final clearWinner = secondScore == null || bestScore - secondScore >= margin;
  return MatchResult(
    best,
    bestScore,
    secondScore: secondScore,
    accepted: bestScore >= threshold && clearWinner,
  );
}

/// Đếm số khung hình liên tiếp cùng khớp một học viên.
///
/// Mỗi khung hình gọi [add] với id học viên khớp (hoặc `null` nếu không khớp).
/// Đổi người hoặc không khớp thì đếm lại từ đầu.
class ConsecutiveMatchCounter<K> {
  ConsecutiveMatchCounter(this.required);

  /// Số khung hình liên tiếp cần đạt.
  final int required;

  K? _current;
  int _count = 0;

  int get count => _count;

  /// Trả về `true` khi đã đủ [required] khung liên tiếp cùng một [key].
  bool add(K? key) {
    if (key == null) {
      reset();
      return false;
    }
    if (key == _current) {
      _count++;
    } else {
      _current = key;
      _count = 1;
    }
    return _count >= required;
  }

  void reset() {
    _current = null;
    _count = 0;
  }
}

/// Mẫu [sample] có thuộc cùng người với các mẫu [previous] đã chụp không:
/// so với vector trung bình của các mẫu trước, đạt [minSimilarity] là được.
/// Chưa có mẫu nào thì luôn đúng.
bool isConsistentSample(
  List<double> sample,
  List<List<double>> previous, {
  required double minSimilarity,
}) {
  if (previous.isEmpty) return true;
  return cosineSimilarity(sample, averageEmbedding(previous)) >= minSimilarity;
}
