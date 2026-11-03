import 'package:flutter/material.dart';

/// Nội dung một bước: dòng đầu là thao tác chính, các dòng sau là ý chi tiết
/// (cách làm, dấu hiệu nhận biết, lưu ý) hiện thành gạch đầu dòng.
/// Bước chỉ có 1 dòng (bài cộng đồng cũ) hiện như văn bản thường.
class StepInstruction extends StatelessWidget {
  const StepInstruction({super.key, required this.text, this.large = false});

  final String text;

  /// true ở màn hình nấu: chữ to để đọc từ xa
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const SizedBox.shrink();

    final mainStyle = large
        ? theme.textTheme.headlineSmall?.copyWith(height: 1.4)
        : theme.textTheme.bodyLarge;
    final detailStyle = large
        ? theme.textTheme.titleMedium?.copyWith(height: 1.4, fontWeight: FontWeight.normal)
        : theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(lines.first, style: mainStyle),
        if (lines.length > 1) SizedBox(height: large ? 16 : 6),
        for (final line in lines.skip(1))
          Padding(
            padding: EdgeInsets.only(bottom: large ? 10 : 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: large ? 2 : 1, right: 8),
                  child: Icon(
                    Icons.check_circle_outline,
                    size: large ? 20 : 16,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Expanded(child: Text(line, style: detailStyle)),
              ],
            ),
          ),
      ],
    );
  }
}
