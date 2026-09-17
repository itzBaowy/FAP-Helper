import 'package:flutter/material.dart';

import '../domain/markbook.dart';
import '../domain/attendance_reset.dart';

class ResetAttendanceDialog extends StatefulWidget {
  const ResetAttendanceDialog({super.key, required this.book});
  final Markbook book;
  @override
  State<ResetAttendanceDialog> createState() => _ResetAttendanceDialogState();
}

class _ResetAttendanceDialogState extends State<ResetAttendanceDialog> {
  late String _scope = widget.book.groups.first.id;
  String _confirmation = '';

  @override
  Widget build(BuildContext context) {
    final groups = widget.book.groups.where(
      (g) => _scope == '*' || g.id == _scope,
    );
    final hasData = groups.any(
      (g) => hasAttendanceToReset(widget.book.attendanceFor(g.id)),
    );
    final marks = groups.fold<int>(
      0,
      (count, g) =>
          count +
          widget.book
              .attendanceFor(g.id)
              .sessions
              .fold<int>(0, (n, s) => n + s.marks.length),
    );
    return AlertDialog(
      title: const Text('Reset dữ liệu điểm danh'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _scope,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Phạm vi reset'),
                items: [
                  for (final g in widget.book.groups)
                    DropdownMenuItem(value: g.id, child: Text(g.label)),
                  const DropdownMenuItem(
                    value: '*',
                    child: Text('Toàn bộ kỳ FA26'),
                  ),
                ],
                onChanged: (value) => setState(() => _scope = value!),
              ),
              const SizedBox(height: 16),
              Text(
                '${groups.length} lớp học phần · $marks dấu P/A sẽ bị xóa.\nCác buổi đã mở/chốt trở về chưa mở.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Giữ sinh viên, lịch học, tổng số buổi, ngày nghỉ, học bù, cấu hình và lịch sử thao tác. App tự sao lưu dữ liệu trước khi reset.',
              ),
              const SizedBox(height: 16),
              if (!hasData)
                const Text('Phạm vi này chưa có dữ liệu điểm danh để reset.'),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Nhập RESET để xác nhận',
                ),
                onChanged: (value) => setState(() => _confirmation = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: hasData && _confirmation == 'RESET'
              ? () => Navigator.pop(context, _scope)
              : null,
          child: const Text('Xác nhận reset'),
        ),
      ],
    );
  }
}
