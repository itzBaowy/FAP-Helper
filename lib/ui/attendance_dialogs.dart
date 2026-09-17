import 'package:flutter/material.dart';

import '../domain/attendance_models.dart';
import '../domain/markbook.dart';
import 'widgets.dart';

Future<String?> attendanceInput(
  BuildContext context, {
  required String title,
  required String description,
  String initial = '',
  bool total = false,
}) => showDialog<String>(
  context: context,
  builder: (_) => _InputDialog(
    title: title,
    description: description,
    initial: initial,
    total: total,
  ),
);

class _InputDialog extends StatefulWidget {
  const _InputDialog({
    required this.title,
    required this.description,
    required this.initial,
    required this.total,
  });
  final String title, description, initial;
  final bool total;
  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.description),
            const SizedBox(height: 20),
            TextFormField(
              key: const ValueKey('attendance-input'),
              controller: _controller,
              autofocus: true,
              maxLines: widget.total ? 1 : 3,
              keyboardType: widget.total
                  ? TextInputType.number
                  : TextInputType.multiline,
              decoration: InputDecoration(
                labelText: widget.total ? 'Số buổi theo lịch tuần' : 'Lý do',
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                if (!widget.total) {
                  return text.length < 3 ? 'Nhập lý do ít nhất 3 ký tự.' : null;
                }
                if (text.isEmpty) return null;
                final number = int.tryParse(text);
                return number == null || number < 1 || number > 200
                    ? 'Nhập số nguyên từ 1 đến 200 hoặc để trống.'
                    : null;
              },
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
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _controller.text.trim());
          }
        },
        child: const Text('Lưu'),
      ),
    ],
  );
}

class MakeupInput {
  const MakeupInput(this.date, this.slot, this.reason);
  final DateTime date;
  final int slot;
  final String reason;
}

class MakeupDialog extends StatefulWidget {
  const MakeupDialog({super.key, required this.now});
  final DateTime now;
  @override
  State<MakeupDialog> createState() => _MakeupDialogState();
}

class _MakeupDialogState extends State<MakeupDialog> {
  late DateTime _date = calendarDate(widget.now).isBefore(Markbook.termStart)
      ? Markbook.termStart
      : calendarDate(widget.now);
  int _slot = 1;
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Thêm buổi học bù'),
    content: SizedBox(
      width: 470,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Chọn ngày và slot thực tế. Nếu thay cho một buổi nghỉ, hãy đánh dấu nghỉ buổi cũ để tổng số buổi không bị tăng.',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: Markbook.termStart,
                  lastDate: DateTime(_date.year + 2, 12, 31),
                );
                if (date != null && mounted) setState(() => _date = date);
              },
              icon: const Icon(Icons.calendar_month),
              label: Text(dateLabel(_date)),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _slot,
              decoration: const InputDecoration(labelText: 'Slot học'),
              items: TeachingSlot.all
                  .map(
                    (slot) => DropdownMenuItem(
                      value: slot.number,
                      child: Text('Slot ${slot.number} · ${slot.label}'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _slot = value!),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reason,
              decoration: const InputDecoration(labelText: 'Lý do học bù'),
              maxLines: 2,
              validator: (value) => (value ?? '').trim().length < 3
                  ? 'Nhập lý do ít nhất 3 ký tự.'
                  : null,
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
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(
              context,
              MakeupInput(_date, _slot, _reason.text.trim()),
            );
          }
        },
        child: const Text('Thêm buổi'),
      ),
    ],
  );
}

Future<void> showAttendanceHistory(
  BuildContext context,
  CourseGroup group,
  CourseAttendance data,
) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    child: SizedBox(
      width: 940,
      height: 640,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Lịch sử · ${group.label}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng lịch sử',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: data.history.isEmpty
                  ? const EmptyState(
                      title: 'Chưa có thay đổi',
                      message: 'Các thao tác điểm danh và sửa dữ liệu sẽ được ghi lại ở đây.',
                    )
                  : ListView.separated(
                      itemCount: data.history.length,
                      separatorBuilder: (_, index) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final event = data.history.reversed.elementAt(index);
                        final at = event.at.toUtc().add(
                          const Duration(hours: 7),
                        );
                        final label = switch (event.action) {
                          'open' => 'Mở buổi',
                          'mark' => 'Điểm danh thủ công',
                          'qr_present' => 'Điểm danh QR · Google',
                          'correct' => 'Sửa sau khi chốt',
                          'close_absent' => 'Chốt: chưa ghi nhận → A',
                          'close' => 'Chốt buổi',
                          'total' => 'Đổi tổng số buổi',
                          'cancel' => 'Đánh dấu nghỉ',
                          'restore' => 'Khôi phục buổi',
                          'makeup' => 'Thêm buổi học bù',
                          'reset' => 'Reset dữ liệu điểm danh',
                          _ => event.action,
                        };
                        return ListTile(
                          leading: const Icon(Icons.history, color: teal),
                          title: Text(
                            '$label${event.rollNumber == null ? '' : ' · ${event.rollNumber}'}',
                          ),
                          subtitle: Text(
                            '${event.sessionId ?? 'Cấu hình lớp'}${event.before != null || event.after != null ? ' · ${event.before ?? '—'} → ${event.after ?? '—'}' : ''}'
                            '${event.reason.isEmpty ? '' : '\nLý do: ${event.reason}'}',
                          ),
                          trailing: Text(
                            '${dateLabel(at)}\n${TeachingSlot.timeLabel(at.hour * 60 + at.minute)} GMT+7',
                            textAlign: TextAlign.right,
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  ),
);
