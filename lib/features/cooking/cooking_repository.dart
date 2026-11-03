import '../../core/api_client.dart';

class CookingSessionInfo {
  const CookingSessionInfo({required this.id, required this.currentStep});
  final int id;
  final int currentStep;

  factory CookingSessionInfo.fromJson(Map<String, dynamic> json) => CookingSessionInfo(
        id: json['id'] as int,
        currentStep: json['currentStep'] as int,
      );
}

class InProgressItem {
  const InProgressItem({
    required this.sessionId,
    required this.recipeId,
    required this.recipeName,
    required this.currentStep,
    required this.totalSteps,
  });
  final int sessionId;
  final int recipeId;
  final String recipeName;
  final int currentStep;
  final int totalSteps;

  factory InProgressItem.fromJson(Map<String, dynamic> json) => InProgressItem(
        sessionId: json['sessionId'] as int,
        recipeId: json['recipeId'] as int,
        recipeName: json['recipeName'] as String,
        currentStep: json['currentStep'] as int,
        totalSteps: json['totalSteps'] as int,
      );
}

class HistoryItem {
  const HistoryItem({
    required this.sessionId,
    required this.recipeId,
    required this.recipeName,
    required this.completedAt,
  });
  final int sessionId;
  final int recipeId;
  final String recipeName;
  final DateTime completedAt;

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        sessionId: json['sessionId'] as int,
        recipeId: json['recipeId'] as int,
        recipeName: json['recipeName'] as String,
        completedAt: DateTime.parse(json['completedAt'] as String).toLocal(),
      );
}

class Progress {
  const Progress({
    required this.completedCount,
    required this.inProgress,
    required this.history,
  });
  final int completedCount;
  final List<InProgressItem> inProgress;
  final List<HistoryItem> history;

  factory Progress.fromJson(Map<String, dynamic> json) => Progress(
        completedCount: json['completedCount'] as int,
        inProgress: (json['inProgress'] as List)
            .map((e) => InProgressItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        history: (json['history'] as List)
            .map((e) => HistoryItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Phiên nấu và tiến độ (KE_HOACH_v2 mục 5). Tất cả cần đăng nhập.
class CookingRepository {
  CookingRepository(this._api);
  final ApiClient _api;

  /// Nếu đã có phiên dở của món này thì server trả lại phiên đó (currentStep có thể > 1).
  Future<CookingSessionInfo> start(int recipeId, int servings) async {
    final json = await _api.post<Map<String, dynamic>>('/cooking-sessions',
        body: {'recipeId': recipeId, 'servings': servings});
    return CookingSessionInfo.fromJson(json);
  }

  Future<void> updateStep(int sessionId, int step) =>
      _api.patch<dynamic>('/cooking-sessions/$sessionId', body: {'currentStep': step});

  Future<void> complete(int sessionId) =>
      _api.post<dynamic>('/cooking-sessions/$sessionId/complete');

  Future<Progress> progress() async =>
      Progress.fromJson(await _api.get<Map<String, dynamic>>('/users/me/progress'));
}
