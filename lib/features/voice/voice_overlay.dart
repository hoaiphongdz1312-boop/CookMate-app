import 'package:flutter/material.dart';

import 'voice_controller.dart';

/// Bảng "Bạn cần gì?" nổi trên mọi màn hình khi nghe "bếp ơi".
/// Tự đóng khi cổng hết cửa sổ chờ lệnh (5 giây) hoặc đã nhận lệnh; chạm vào bảng để đóng ngay.
class VoiceOverlay extends StatelessWidget {
  const VoiceOverlay({super.key, required this.voice, required this.child});

  final VoiceController voice;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        ListenableBuilder(
          listenable: voice,
          builder: (context, _) => Positioned(
            left: 16,
            right: 16,
            bottom: 96 + MediaQuery.paddingOf(context).bottom,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: voice.panelVisible
                  ? _Panel(
                      key: ValueKey(voice.notice),
                      notice: voice.notice,
                      onClose: voice.dismissPanel,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.notice, required this.onClose});

  final String? notice;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      elevation: 6,
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onClose,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: scheme.primary,
                child: Icon(
                  notice == null ? Icons.mic : Icons.info_outline,
                  color: scheme.onPrimary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: notice != null
                      ? [
                          Text(notice!,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(color: scheme.onPrimaryContainer)),
                        ]
                      : [
                          Text('Bạn cần gì?',
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(color: scheme.onPrimaryContainer)),
                          const SizedBox(height: 4),
                          Text(
                            'Thử nói: "hôm nay ăn gì", "mở món đang nấu", "về trang chủ"',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.onPrimaryContainer),
                          ),
                        ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
