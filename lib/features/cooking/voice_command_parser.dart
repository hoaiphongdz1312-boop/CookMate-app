/// Các lệnh giọng nói. Lệnh nấu ăn chỉ dùng được ở màn nấu (khớp với CookingController);
/// lệnh điều hướng dùng ở mọi màn.
enum VoiceCommand {
  next(cooking: true),
  previous(cooking: true),
  startTimer(cooking: true),
  pauseTimer(cooking: true),
  openCooking(cooking: false),
  goHome(cooking: false),
  luckyMeal(cooking: false);

  const VoiceCommand({required this.cooking});

  /// true = cần đang ở màn nấu
  final bool cooking;
}

// Bảng bỏ dấu tiếng Việt: mỗi chuỗi là một nhóm chữ có dấu -> chữ gốc.
const _diacriticGroups = <String, String>{
  'àáạảãâầấậẩẫăằắặẳẵ': 'a',
  'èéẹẻẽêềếệểễ': 'e',
  'ìíịỉĩ': 'i',
  'òóọỏõôồốộổỗơờớợởỡ': 'o',
  'ùúụủũưừứựửữ': 'u',
  'ỳýỵỷỹ': 'y',
  'đ': 'd',
};

final Map<String, String> _diacriticMap = {
  for (final e in _diacriticGroups.entries)
    for (final ch in e.key.split('')) ch: e.value,
};

/// Chữ thường, bỏ dấu (đ -> d), gộp khoảng trắng. Ký tự lạ giữ nguyên.
String normalizeVoiceText(String input) {
  final buffer = StringBuffer();
  for (final ch in input.toLowerCase().split('')) {
    buffer.write(_diacriticMap[ch] ?? ch);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Câu (đã chuẩn hóa) có chứa cụm gọi "bếp ơi" không.
bool containsWakeWord(String normalized) => normalized.contains('bep oi');

// Thứ tự quan trọng: "dung hen gio" phải xét trước "hen gio".
// Lệnh điều hướng xét trước để "mo mon dang nau" không bị bắt nhầm thành lệnh khác.
const _commandPhrases = <(VoiceCommand, List<String>)>[
  (VoiceCommand.openCooking, ['mo mon dang nau']),
  (VoiceCommand.goHome, ['ve trang chu']),
  (VoiceCommand.luckyMeal, ['hom nay an gi']),
  (VoiceCommand.pauseTimer, ['dung hen gio', 'tam dung']),
  (VoiceCommand.startTimer, ['bat dau hen gio', 'hen gio']),
  (VoiceCommand.next, ['buoc tiep theo', 'tiep theo']),
  (VoiceCommand.previous, ['buoc truoc', 'quay lai']),
];

/// Tìm lệnh trong câu (đã chuẩn hóa); null nếu không có.
VoiceCommand? findVoiceCommand(String normalized) {
  for (final (command, phrases) in _commandPhrases) {
    for (final phrase in phrases) {
      if (normalized.contains(phrase)) return command;
    }
  }
  return null;
}
