import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import 'community_models.dart';
import 'community_repository.dart';

/// Hỏi lý do rồi gửi báo cáo vi phạm. Trả về true nếu đã gửi (hoặc đã báo cáo từ trước).
Future<bool> reportRecipe(BuildContext context, CommunityRepository repo, int recipeId) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await showDialog<(ReportReason, String)>(
    context: context,
    builder: (_) => const ReportDialog(),
  );
  if (result == null) return false;
  try {
    await repo.report(recipeId, result.$1, detail: result.$2);
    messenger.showSnackBar(const SnackBar(content: Text('Đã gửi báo cáo, admin sẽ xem xét. Cảm ơn bạn!')));
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    // 409: đã báo cáo bài này rồi, coi như xong
    return e.statusCode == 409;
  }
}

/// Xác nhận rồi chặn tác giả. Trả về true nếu đã chặn.
Future<bool> blockUser(
  BuildContext context,
  CommunityRepository repo,
  int userId,
  String? name,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final who = name ?? 'người dùng này';
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Chặn $who?'),
      content: const Text(
          'Bạn sẽ không còn thấy bài của người này trong tab Cộng đồng. '
          'Có thể bỏ chặn trong Hồ sơ > Người dùng đã chặn.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Chặn')),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await repo.block(userId);
    messenger.showSnackBar(SnackBar(content: Text('Đã chặn $who')));
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

/// Chọn lý do báo cáo; lý do "Khác" bắt buộc mô tả. Trả về (lý do, mô tả).
class ReportDialog extends StatefulWidget {
  const ReportDialog({super.key});

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  final _detail = TextEditingController();
  ReportReason? _reason;
  String? _error;

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Vui lòng chọn lý do');
      return;
    }
    if (reason == ReportReason.other && _detail.text.trim().isEmpty) {
      setState(() => _error = 'Vui lòng mô tả vi phạm');
      return;
    }
    Navigator.pop(context, (reason, _detail.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Báo cáo vi phạm'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (v) => setState(() {
                _reason = v;
                _error = null;
              }),
              child: Column(
                children: [
                  for (final r in ReportReason.values)
                    RadioListTile<ReportReason>(
                      value: r,
                      title: Text(r.label),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
            TextField(
              controller: _detail,
              maxLength: 500,
              maxLines: 3,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: _reason == ReportReason.other ? 'Mô tả (bắt buộc)' : 'Mô tả thêm',
                hintText: _reason == ReportReason.other ? null : 'Không bắt buộc',
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        FilledButton(onPressed: _submit, child: const Text('Gửi báo cáo')),
      ],
    );
  }
}
