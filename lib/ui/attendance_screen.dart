import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/attendance_csv.dart';
import '../data/windows_file_picker.dart';
import '../domain/attendance_models.dart';
import '../domain/attendance_service.dart';
import '../domain/markbook.dart';
import 'attendance_dialogs.dart';
import 'roster_dialog.dart';
import 'qr_attendance_dialog.dart';
import 'widgets.dart';

class _AttendanceViewport extends StatelessWidget {
  const _AttendanceViewport({required this.padding, required this.child});
  final EdgeInsetsGeometry padding;
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => SingleChildScrollView(
      child: SizedBox(
        height: bounds.maxHeight < 760 ? 760 : bounds.maxHeight,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({
    super.key,
    required this.book,
    required this.groupId,
    required this.onSave,
    this.now,
    this.initialDate,
    this.initialSessionId,
    this.pickCsv,
    this.exporter,
  });
  final Markbook book;
  final String groupId;
  final Future<void> Function(Markbook) onSave;
  final DateTime Function()? now;
  final DateTime? initialDate;
  final String? initialSessionId;
  final Future<String?> Function(String)? pickCsv;
  final AttendanceCsv? exporter;
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  static const _service = AttendanceService();
  late Markbook _book = widget.book;
  CourseGroup get _group =>
      _book.groups.firstWhere((g) => g.id == widget.groupId);
  CourseAttendance get _data => _book.attendanceFor(widget.groupId);
  late DateTime _now = (widget.now ?? vietnamNow)();
  late DateTime _through = _now.add(const Duration(days: 14));
  String? _selectedId;
  bool _saving = false;
  String _query = '';
  final _search = TextEditingController();
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  Timer? _timer;
  List<ScheduledSession> get _schedule =>
      _service.schedule(_group, _data, _through);
  ScheduledSession get _selected => _schedule.firstWhere(
    (s) => s.session.id == _selectedId,
    orElse: () => _schedule.first,
  );

  @override
  void initState() {
    super.initState();
    if (widget.initialDate != null && widget.initialDate!.isAfter(_through)) {
      _through = widget.initialDate!;
    }
    if (_through.isBefore(Markbook.termStart)) {
      _through = Markbook.termStart.add(const Duration(days: 14));
    }
    _selectDefault(widget.initialDate);
    if (widget.initialSessionId != null &&
        _schedule.any((s) => s.session.id == widget.initialSessionId)) {
      _selectedId = widget.initialSessionId;
    }
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        setState(() {
          _now = (widget.now ?? vietnamNow)();
        });
      }
    });
  }

  void _selectDefault([DateTime? date]) {
    final sessions = _schedule;
    final day = calendarDate(date ?? _now);
    _selectedId =
        sessions
            .where((s) => s.session.state == SessionState.open)
            .firstOrNull
            ?.session
            .id ??
        sessions
            .where(
              (s) =>
                  s.session.date == day &&
                  s.session.state != SessionState.cancelled,
            )
            .firstOrNull
            ?.session
            .id ??
        sessions
            .where(
              (s) =>
                  s.session.date.isBefore(day) &&
                  s.session.state != SessionState.cancelled,
            )
            .lastOrNull
            ?.session
            .id ??
        sessions.first.session.id;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  Future<void> _error(Object error) async {
    final message = error is FormatException
        ? error.message
        : error is FileSystemException
        ? 'Không ghi được file. Kiểm tra quyền truy cập, dung lượng và file có đang mở trong Excel không.'
        : error is PlatformException
        ? (error.message ?? 'Không mở được hộp thoại lưu file.')
        : 'Thao tác chưa hoàn tất. Vui lòng thử lại.';
    if (!mounted) return;
    setState(() => _saving = false);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chưa thể thực hiện'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _commit(Markbook Function() change, {String? success}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final next = change();
      if (!identical(next, _book)) await widget.onSave(next);
      if (!mounted) return;
      setState(() => _book = next);
      if (success != null) _toast(success);
    } catch (error) {
      await _error(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );

  Future<void> _mark(Student student, AttendanceMark? value) async {
    final session = _selected.session;
    if (session.marks[student.rollNumber] == value) return;
    var reason = '';
    if (session.state == SessionState.closed) {
      final response = await attendanceInput(
        context,
        title: 'Sửa điểm danh sau khi chốt',
        description:
            '${student.fullName} · ${student.rollNumber}\n${_selected.label}, ${dateLabel(session.date)}: ${session.marks[student.rollNumber]?.code ?? '—'} → ${value?.code ?? '—'}',
      );
      if (response == null || !mounted) return;
      reason = response;
    }
    await _commit(
      () => _service.mark(
        _book,
        widget.groupId,
        session.id,
        student.rollNumber,
        value,
        _now,
        reason: reason,
      ),
    );
  }

  Future<void> _close() async {
    final session = _selected.session;
    final unmarked = _group.students.length - session.marks.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Chốt ${_selected.label.toLowerCase()}?'),
        content: Text(
          '${_group.label} · ${dateLabel(session.date)} · Slot ${session.slot}\n\n'
          '$unmarked sinh viên chưa ghi nhận sẽ chuyển thành A. Áp dụng cho toàn bộ ${_group.students.length} SV, kể cả những người đang bị ẩn bởi tìm kiếm. Kết quả P/A đã ghi được giữ nguyên.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xác nhận chốt'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _commit(
      () => _service.close(_book, widget.groupId, session.id, _now),
      success: 'Đã chốt buổi. Có thể xuất CSV.',
    );
  }

  Future<void> _qr() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => QrAttendanceDialog(
        groupId: widget.groupId,
        sessionId: _selected.session.id,
        readBook: () => _book,
        onSave: (next) async {
          await widget.onSave(next);
          if (mounted) setState(() => _book = next);
        },
      ),
    );
  }

  Future<void> _setTotal() async {
    final value = await attendanceInput(
      context,
      title: 'Cấu hình tổng số buổi',
      total: true,
      initial: _data.plannedTotal?.toString() ?? '',
      description: 'Nhập số buổi theo lịch tuần gốc của lớp. Buổi nghỉ sẽ được trừ và buổi học bù được cộng vào tổng phải học. Để trống nếu chưa xác định; tỷ lệ vắng sẽ hiển thị —.',
    );
    if (value == null || !mounted) return;
    await _commit(
      () => _service.setTotal(
        _book,
        widget.groupId,
        value.isEmpty ? null : int.parse(value),
        _now,
      ),
      success: 'Đã lưu cấu hình tổng số buổi.',
    );
  }

  Future<void> _cancel() async {
    final session = _selected.session;
    final reason = await attendanceInput(
      context,
      title: 'Đánh dấu buổi nghỉ',
      description:
          '${dateLabel(session.date)} · Slot ${session.slot}. Buổi nghỉ không tạo A và không tính vào tổng số buổi phải học.',
    );
    if (reason == null || !mounted) return;
    await _commit(
      () => _service.cancel(_book, widget.groupId, session.id, _now, reason),
    );
  }

  Future<void> _makeup() async {
    final input = await showDialog<MakeupInput>(
      context: context,
      builder: (_) => MakeupDialog(now: _now),
    );
    if (input == null || !mounted) return;
    await _commit(
      () => _service.addMakeup(
        _book,
        widget.groupId,
        input.date,
        input.slot,
        _now,
        input.reason,
      ),
      success: 'Đã thêm buổi học bù.',
    );
    if (mounted &&
        _data.sessions.any(
          (s) => s.id == '${dayKey(input.date)}/${input.slot}',
        )) {
      setState(() => _selectedId = '${dayKey(input.date)}/${input.slot}');
    }
  }

  Future<void> _export(bool allClosed) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final exporter = widget.exporter ?? AttendanceCsv();
      final session = _selected.session;
      final content = exporter.generate(
        _book,
        widget.groupId,
        DateTime.now(),
        sessionId: allClosed ? null : session.id,
      );
      final suffix = allClosed
          ? 'all_closed'
          : '${dayKey(session.date)}_slot${session.slot}';
      final path = await (widget.pickCsv ?? WindowsFilePicker().saveCsv)(
        'FA26_${_group.subjectCode}_${_group.classCode}_$suffix.csv',
      );
      if (path == null) return;
      await exporter.save(path, content);
      if (mounted) _toast('Đã xuất CSV: $path');
    } catch (error) {
      await _error(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _stateLabel(SessionState state) => switch (state) {
    SessionState.planned => 'Chưa mở',
    SessionState.open => 'Đang điểm danh',
    SessionState.closed => 'Đã chốt',
    SessionState.cancelled => 'Buổi nghỉ',
  };

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final session = selected.session;
    final schedule = _schedule;
    final filtered = _group.students
        .where(
          (s) => '${s.rollNumber} ${s.fullName} ${s.email} ${s.memberCode}'
              .toLowerCase()
              .contains(_query),
        )
        .toList();
    final total = _service.requiredTotal(_data);
    final selectedIndex = schedule.indexWhere(
      (s) => s.session.id == session.id,
    );
    final pageStart = selectedIndex ~/ 8 * 8;
    final visible = schedule.skip(pageStart).take(8).toList();
    final present = session.marks.values
        .where((m) => m == AttendanceMark.present)
        .length;
    final absent = session.marks.values
        .where((m) => m == AttendanceMark.absent)
        .length;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Đóng',
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            _group.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          actions: [
            TextButton.icon(
              onPressed: _saving ? null : () => showRoster(context, _group),
              icon: const Icon(Icons.people_outline),
              label: const Text('Danh sách SV'),
            ),
            const SizedBox(width: 16),
          ],
        ),
        body: _AttendanceViewport(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_saving) const LinearProgressIndicator(minHeight: 2),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Tag('FA26'),
                  Tag('${_group.students.length} sinh viên'),
                  Tag(_group.daysLabel),
                  Tag('Tổng phải học: ${total ?? 'chưa xác định'}'),
                  TextButton.icon(
                    onPressed: _saving ? null : _setTotal,
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('Tổng số buổi'),
                  ),
                  TextButton.icon(
                    onPressed: _saving ? null : _makeup,
                    icon: const Icon(Icons.event_available, size: 18),
                    label: const Text('Thêm học bù'),
                  ),
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => showAttendanceHistory(context, _group, _data),
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Lịch sử'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Surface(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 305,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('session-select-${session.id}'),
                            isExpanded: true,
                            initialValue: session.id,
                            decoration: const InputDecoration(
                              labelText: 'Buổi đang chọn',
                              isDense: true,
                            ),
                            items: schedule
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s.session.id,
                                    child: Text(
                                      '${s.label} · ${dateLabel(s.session.date)} · Slot ${s.session.slot}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _saving
                                ? null
                                : (value) =>
                                      setState(() => _selectedId = value),
                          ),
                        ),
                        Tag(_stateLabel(session.state)),
                        if (_service.isCurrent(session, _now))
                          const Tag('Đang trong giờ'),
                        Text(
                          TeachingSlot.all[session.slot - 1].label,
                          style: const TextStyle(color: muted),
                        ),
                        if (session.isMakeup) const Tag('Học bù'),
                        if (session.state == SessionState.planned)
                          FilledButton.icon(
                            key: const ValueKey('open-session'),
                            onPressed:
                                _saving || !_service.hasStarted(session, _now)
                                ? null
                                : () => _commit(
                                    () => _service.open(
                                      _book,
                                      widget.groupId,
                                      session.id,
                                      _now,
                                    ),
                                  ),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Mở buổi'),
                          ),
                        if (session.state == SessionState.open)
                          OutlinedButton.icon(
                            onPressed: _saving ? null : _qr,
                            icon: const Icon(Icons.qr_code_2),
                            label: const Text('Điểm danh QR'),
                          ),
                        if (session.state == SessionState.open)
                          FilledButton.icon(
                            onPressed: _saving ? null : _close,
                            icon: const Icon(Icons.lock_outline),
                            label: const Text('Chốt danh sách'),
                          ),
                        if (session.state == SessionState.planned)
                          TextButton(
                            onPressed: _saving ? null : _cancel,
                            child: const Text('Đánh dấu nghỉ'),
                          ),
                        if (session.state == SessionState.cancelled)
                          OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => _commit(
                                    () => _service.restore(
                                      _book,
                                      widget.groupId,
                                      session.id,
                                      _now,
                                    ),
                                  ),
                            child: const Text('Khôi phục buổi'),
                          ),
                        PopupMenuButton<bool>(
                          tooltip: 'Xuất CSV',
                          enabled:
                              !_saving &&
                              _data.sessions.any(
                                (s) => s.state == SessionState.closed,
                              ),
                          onSelected: _export,
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: false,
                              enabled: session.state == SessionState.closed,
                              child: const Text('Xuất buổi đang chọn'),
                            ),
                            const PopupMenuItem(
                              value: true,
                              child: Text('Xuất tất cả buổi đã chốt'),
                            ),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.download_outlined, color: teal),
                                SizedBox(width: 6),
                                Text(
                                  'Xuất CSV',
                                  style: TextStyle(
                                    color: teal,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      session.state == SessionState.cancelled
                          ? 'Buổi nghỉ: ${session.note}'
                          : 'Buổi đang chọn: $present P · $absent A · ${_group.students.length - present - absent} chưa ghi nhận'
                                '${session.state == SessionState.planned ? (_service.hasStarted(session, _now) ? ' · Bấm Mở buổi để điểm danh.' : ' · Chưa đến giờ mở buổi.') : ''}',
                      style: const TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Tìm MSSV, họ tên hoặc email',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Các buổi trước',
                    onPressed: _saving || pageStart == 0
                        ? null
                        : () => setState(
                            () => _selectedId =
                                schedule[(pageStart - 8).clamp(
                                      0,
                                      schedule.length - 1,
                                    )]
                                    .session
                                    .id,
                          ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    '${pageStart + 1}–${pageStart + visible.length}/${schedule.length}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  IconButton(
                    tooltip: 'Các buổi tiếp',
                    onPressed: _saving || pageStart + 8 >= schedule.length
                        ? null
                        : () => setState(
                            () => _selectedId =
                                schedule[pageStart + 8].session.id,
                          ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _through = _now.add(const Duration(days: 14));
                            _selectDefault();
                          }),
                    child: const Text('Hôm nay'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filtered.isEmpty
                    ? const Surface(
                        child: EmptyState(
                          title: 'Không tìm thấy sinh viên',
                          message: 'Thử tìm bằng MSSV hoặc một phần họ tên.',
                          icon: Icons.person_search_outlined,
                        ),
                      )
                    : Surface(
                        padding: EdgeInsets.zero,
                        child: Scrollbar(
                          controller: _vertical,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _vertical,
                            child: Scrollbar(
                              controller: _horizontal,
                              thumbVisibility: true,
                              notificationPredicate: (notification) =>
                                  notification.depth == 0,
                              child: SingleChildScrollView(
                                controller: _horizontal,
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  horizontalMargin: 16,
                                  columnSpacing: 16,
                                  headingRowHeight: 88,
                                  dataRowMinHeight: 48,
                                  dataRowMaxHeight: 56,
                                  headingRowColor: WidgetStateProperty.all(
                                    const Color(0xffedf5f1),
                                  ),
                                  columns: [
                                    const DataColumn(label: Text('MSSV')),
                                    const DataColumn(label: Text('Họ tên')),
                                    const DataColumn(label: Text('P')),
                                    const DataColumn(label: Text('A')),
                                    const DataColumn(label: Text('Vắng %')),
                                    for (final item in visible)
                                      DataColumn(label: _sessionHeader(item)),
                                  ],
                                  rows: [
                                    for (final student in filtered)
                                      _studentRow(student, visible),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              Text(
                '${filtered.length}/${_group.students.length} SV · P: có mặt · A: vắng · —: chưa ghi nhận · Chỉ sửa cột đang chọn.'
                '${total == null ? '\nChưa có tổng số buổi: chưa tính tỷ lệ vắng. Lịch dự kiến hiển thị đến ${dateLabel(_through)}.' : '\nTỷ lệ vắng = số A / $total buổi phải học × 100%. Buổi chưa chốt không tự tạo A.'}',
                style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sessionHeader(ScheduledSession item) {
    final session = item.session;
    final selected = session.id == _selected.session.id;
    final current = _service.isCurrent(session, _now);
    return InkWell(
      onTap: _saving ? null : () => setState(() => _selectedId = session.id),
      child: Container(
        width: 94,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xffd3eddf) : null,
          border: Border(
            bottom: BorderSide(
              color: current
                  ? teal
                  : selected
                  ? const Color(0xff163c3a)
                  : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              item.label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              '${session.date.day.toString().padLeft(2, '0')}/${session.date.month.toString().padLeft(2, '0')} · S${session.slot}',
              style: const TextStyle(fontSize: 11),
            ),
            Text(
              current ? 'Đang trong giờ' : _stateLabel(session.state),
              style: const TextStyle(fontSize: 10, color: muted),
            ),
          ],
        ),
      ),
    );
  }

  DataRow _studentRow(Student student, List<ScheduledSession> visible) {
    final summary = _service.summary(_data, student.rollNumber);
    return DataRow(
      cells: [
        DataCell(SelectableText(student.rollNumber)),
        DataCell(
          Tooltip(
            message: '${student.email}\n${student.memberCode}',
            child: SizedBox(
              width: 170,
              child: Text(
                student.fullName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        DataCell(Text('${summary.present}')),
        DataCell(Text('${summary.absent}')),
        DataCell(
          Text(
            summary.absencePercent == null
                ? '—'
                : '${summary.absencePercent!.toStringAsFixed(1)}%',
          ),
        ),
        for (final item in visible) DataCell(_markCell(student, item.session)),
      ],
    );
  }

  Widget _markCell(Student student, AttendanceSession session) {
    final selected = session.id == _selected.session.id;
    final mark = session.marks[student.rollNumber];
    final editable =
        !_saving &&
        selected &&
        [SessionState.open, SessionState.closed].contains(session.state);
    final color = mark == AttendanceMark.present
        ? teal
        : mark == AttendanceMark.absent
        ? const Color(0xffb04435)
        : muted;
    final cell = Container(
      width: 94,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? const Color(0xfff0f7f4) : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        session.state == SessionState.cancelled ? 'Nghỉ' : mark?.code ?? '—',
        style: TextStyle(fontWeight: FontWeight.w700, color: color),
      ),
    );
    if (!editable) return cell;
    return PopupMenuButton<String>(
      key: ValueKey('mark-${student.rollNumber}-${session.id}'),
      tooltip: 'Điểm danh ${student.rollNumber}',
      onSelected: (value) =>
          _mark(student, value == '-' ? null : parseMark(value)),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'P', child: Text('P · Có mặt')),
        const PopupMenuItem(value: 'A', child: Text('A · Vắng')),
        if (session.state == SessionState.open)
          const PopupMenuItem(value: '-', child: Text('— · Chưa ghi nhận')),
      ],
      child: cell,
    );
  }
}
