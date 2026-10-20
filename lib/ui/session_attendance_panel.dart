import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/attendance_models.dart';
import '../domain/markbook.dart';
import '../domain/session_attendance_report.dart';
import 'widgets.dart';

class SessionAttendancePanel extends StatefulWidget {
  const SessionAttendancePanel({
    super.key,
    required this.group,
    required this.data,
    required this.session,
  });

  final CourseGroup group;
  final CourseAttendance data;
  final AttendanceSession session;

  @override
  State<SessionAttendancePanel> createState() => _SessionAttendancePanelState();
}

class _SessionAttendancePanelState extends State<SessionAttendancePanel> {
  AttendanceFilter _filter = AttendanceFilter.present;
  bool _newestFirst = true;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  late SessionAttendanceReport _report = _buildReport();

  SessionAttendanceReport _buildReport() => SessionAttendanceReport(
    group: widget.group,
    data: widget.data,
    session: widget.session,
  );

  @override
  void didUpdateWidget(SessionAttendancePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.group, widget.group) ||
        !identical(oldWidget.data, widget.data) ||
        !identical(oldWidget.session, widget.session)) {
      _report = _buildReport();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _report.select(
      filter: _filter,
      query: _search.text,
      newestFirst: _newestFirst,
    );
    final present = _report.count(AttendanceFilter.present);
    return Surface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Danh sách điểm danh',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Cập nhật sau mỗi lần lưu thành công · Giờ Việt Nam (GMT+7)',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _report.entries.isEmpty
                ? 0
                : present / _report.entries.length,
            semanticsLabel:
                '$present/${_report.entries.length} sinh viên có mặt',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final filter in AttendanceFilter.values)
                ChoiceChip(
                  key: ValueKey('qr-filter-${filter.name}'),
                  label: Text('${filter.label} (${_report.count(filter)})'),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('qr-roster-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Tìm MSSV, họ tên hoặc email',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Xóa tìm kiếm',
                      onPressed: () => setState(_search.clear),
                      icon: const Icon(Icons.clear),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${entries.length} kết quả',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _newestFirst = !_newestFirst),
                icon: const Icon(Icons.sort, size: 18),
                label: Text(_newestFirst ? 'Mới cập nhật trước' : 'Theo MSSV'),
              ),
            ],
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                _search.text.trim().isNotEmpty
                    ? 'Không tìm thấy sinh viên với bộ lọc hiện tại.'
                    : _filter == AttendanceFilter.present
                    ? 'Chưa có sinh viên được ghi nhận có mặt.'
                    : 'Không có sinh viên ở trạng thái này.',
                style: const TextStyle(color: muted),
              ),
            )
          else
            SizedBox(
              height: math.min(320, entries.length * 88.0),
              child: Scrollbar(
                controller: _scroll,
                thumbVisibility: true,
                child: ListView.separated(
                  controller: _scroll,
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) => _row(entries[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(SessionAttendanceEntry entry) {
    final at = entry.event?.at.toUtc().add(const Duration(hours: 7));
    final time = at == null
        ? ''
        : ' · ${TeachingSlot.timeLabel(at.hour * 60 + at.minute)}:'
              '${at.second.toString().padLeft(2, '0')}';
    final label = switch (entry.mark) {
      AttendanceMark.present => 'P · Có mặt',
      AttendanceMark.absent => 'A · Vắng',
      null => '— · Chưa ghi nhận',
    };
    return Padding(
      key: ValueKey('qr-attendee-${entry.student.rollNumber}'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            entry.mark == AttendanceMark.present
                ? Icons.check_circle_outline
                : entry.mark == AttendanceMark.absent
                ? Icons.cancel_outlined
                : Icons.pending_outlined,
            size: 20,
            color: entry.mark == AttendanceMark.absent
                ? Colors.red.shade700
                : teal,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.student.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${entry.student.rollNumber} · $label',
                  style: const TextStyle(fontSize: 12),
                ),
                if (entry.mark != null)
                  Text(
                    '${entry.source}$time',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
