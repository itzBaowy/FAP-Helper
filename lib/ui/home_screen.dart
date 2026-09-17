import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/excel_importer.dart';
import '../data/markbook_store.dart';
import '../data/windows_file_picker.dart';
import '../domain/markbook.dart';
import '../domain/attendance_service.dart';
import '../domain/attendance_models.dart';
import 'attendance_screen.dart';
import 'import_dialog.dart';
import 'widgets.dart';
import '../data/qr_settings.dart';
import 'qr_settings_panel.dart';
import 'reset_attendance_dialog.dart';

Future<ImportPreview> readWorkbookFile(String path) async {
  final file = File(path);
  if (await file.length() > ExcelImporter.maxFileBytes) {
    throw const FormatException('File vượt quá giới hạn 25 MB.');
  }
  final name = path.replaceAll('\\', '/').split('/').last;
  return ExcelImporter().parse(await file.readAsBytes(), name);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, this.pickFile, this.now});
  final MarkbookStore store;
  final Future<String?> Function()? pickFile;
  final DateTime Function()? now;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Markbook? _book;
  bool _loading = true;
  bool _busy = false;
  bool _recovered = false;
  String? _loadError;
  int _page = 0;
  String? _subject;
  String _query = '';
  final _search = TextEditingController();
  late DateTime _now;
  DateTime? _selectedDate;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = (widget.now ?? vietnamNow)();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = (widget.now ?? vietnamNow)());
    });
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final result = await widget.store.load();
      if (!mounted) return;
      setState(() {
        _book = result.markbook;
        _recovered = result.recovered;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _message(Object error) {
    if (error is FormatException) return error.message;
    if (error is FileSystemException) {
      return 'Không đọc/ghi được file. Kiểm tra quyền truy cập và dung lượng ổ đĩa. ${error.message}';
    }
    if (error is PlatformException) {
      return error.message ?? 'Không mở được hộp thoại chọn file.';
    }
    return 'Không thể xử lý dữ liệu. Vui lòng thử lại với file .xlsx hợp lệ.';
  }

  Future<void> _import() async {
    if (_busy || _loadError != null) return;
    setState(() => _busy = true);
    try {
      final path = await (widget.pickFile ?? WindowsFilePicker().pickExcel)();
      if (path == null) return;
      final preview = await compute(readWorkbookFile, path);
      if (!mounted) return;
      // Validate compatibility before asking the user to confirm re-import.
      final candidate = preview.canSave
          ? (_book?.mergeImport(preview.markbook) ?? preview.markbook)
          : preview.markbook;
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            ImportDialog(preview: preview, replacing: _book != null),
      );
      if (accepted != true) return;
      await widget.store.save(candidate);
      if (!mounted) return;
      setState(() {
        _book = candidate;
        _subject = null;
        _query = '';
        _search.clear();
        _recovered = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã lưu ${preview.markbook.groups.length} lớp học phần của kỳ FA26.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Chưa thể import'),
          content: Text(_message(error)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetAttendance() async {
    if (_busy || _book == null || _loadError != null) return;
    setState(() => _busy = true);
    try {
      final scope = await showDialog<String>(
        context: context,
        builder: (_) => ResetAttendanceDialog(book: _book!),
      );
      if (scope == null) return;
      final result = await widget.store.reset(
        _book!,
        groupId: scope == '*' ? null : scope,
      );
      if (!mounted) return;
      setState(() {
        _book = result.book;
        _recovered = false;
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Đã reset điểm danh'),
          content: SelectableText(
            result.backupPath == null
                ? 'Không có dữ liệu điểm danh cần reset.'
                : 'Bản sao trước khi reset:\n${result.backupPath}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Chưa thể reset điểm danh'),
          content: Text(_message(error)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _importButton() => FilledButton.icon(
    onPressed: _busy || _loading || _loadError != null ? null : _import,
    icon: _busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.upload_file_outlined, size: 20),
    label: Text(_busy ? 'Đang xử lý…' : 'Import Excel'),
  );

  Future<void> _openClass(
    CourseGroup group, {
    DateTime? date,
    String? sessionId,
  }) async {
    if (_busy || _book == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AttendanceScreen(
          book: _book!,
          groupId: group.id,
          now: widget.now,
          initialDate: date,
          initialSessionId: sessionId,
          onSave: (updated) async {
            await widget.store.save(updated);
            if (mounted) setState(() => _book = updated);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1050;
        return Row(
          children: [
            _sidebar(wide),
            Expanded(
              child: Column(
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.school_outlined,
                          color: teal,
                          size: 21,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Không gian giảng viên',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (constraints.maxWidth >= 800)
                          Text(
                            '${dateLabel(_now)} · ${TeachingSlot.timeLabel(_now.hour * 60 + _now.minute)}  GMT+7',
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        const SizedBox(width: 20),
                        const Tag('FA26'),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (_busy) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : SingleChildScrollView(
                            padding: EdgeInsets.all(wide ? 32 : 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _heading(),
                                const SizedBox(height: 24),
                                if (_page == 3) ...[
                                  QrSettingsPanel(
                                    loadSettings: () => QrSettings.load(
                                      source: File(
                                        '${widget.store.directory.path}${Platform.pathSeparator}qr-settings.json',
                                      ),
                                    ),
                                    saveSettings: (settings) => settings.save(
                                      target: File(
                                        '${widget.store.directory.path}${Platform.pathSeparator}qr-settings.json',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Surface(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Dữ liệu điểm danh',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge,
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Reset theo lớp học phần hoặc toàn bộ kỳ FA26. Có xác nhận và sao lưu trước khi xóa.',
                                        ),
                                        const SizedBox(height: 16),
                                        OutlinedButton.icon(
                                          onPressed:
                                              _book == null ||
                                                  _busy ||
                                                  _loadError != null
                                              ? null
                                              : _resetAttendance,
                                          icon: const Icon(Icons.restart_alt),
                                          label: const Text(
                                            'Reset dữ liệu điểm danh',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else if (_loadError != null) ...[
                                  Notice(_loadError!, error: true),
                                  const SizedBox(height: 16),
                                  SelectableText(
                                    'Thư mục dữ liệu: ${widget.store.directory.path}',
                                  ),
                                  const SizedBox(height: 16),
                                  OutlinedButton(
                                    onPressed: _load,
                                    child: const Text('Thử đọc lại dữ liệu'),
                                  ),
                                ] else if (_book == null)
                                  _welcome()
                                else ...[
                                  if (_recovered) ...[
                                    const Notice(
                                      'Đã đọc bản sao lưu vì dữ liệu chính không đọc được. Hãy kiểm tra danh sách; lần import tiếp theo sẽ giữ lại file lỗi để đối chiếu.',
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                  if (_page == 0) ..._overview(),
                                  if (_page == 1) ...[
                                    _filters(),
                                    const SizedBox(height: 24),
                                    _courseGrid(),
                                  ],
                                  if (_page == 2) ...[
                                    _filters(search: false),
                                    const SizedBox(height: 20),
                                    _weekSchedule(),
                                  ],
                                  const SizedBox(height: 28),
                                  _dataFooter(),
                                ],
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _sidebar(bool wide) => Container(
    width: wide ? 220 : 76,
    color: const Color(0xff103c39),
    child: Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 24 : 16,
            vertical: 30,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xffcdf2df),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.fact_check_outlined,
                  size: 24,
                  color: Color(0xff103c39),
                ),
              ),
              if (wide) ...[
                const SizedBox(width: 12),
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'FAP Helper',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (wide)
          const Padding(
            padding: EdgeInsets.only(left: 26, bottom: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'QUẢN LÝ GIẢNG DẠY',
                style: TextStyle(
                  color: Color(0xff8bb5ac),
                  fontSize: 10,
                  letterSpacing: 1.3,
                ),
              ),
            ),
          ),
        for (final (index, icon, label) in [
          (0, Icons.dashboard_outlined, 'Tổng quan'),
          (1, Icons.menu_book_outlined, 'Lớp học phần'),
          (2, Icons.calendar_view_week_outlined, 'Lịch tuần'),
          (3, Icons.settings_outlined, 'Cấu hình'),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Tooltip(
              message: label,
              child: Material(
                color: _page == index
                    ? const Color(0xff285550)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _page = index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          icon,
                          size: 22,
                          color: _page == index
                              ? const Color(0xffd0f7e0)
                              : const Color(0xffa4c2bd),
                        ),
                        if (wide) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(
                                color: _page == index
                                    ? Colors.white
                                    : const Color(0xffb5d0ca),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        if (wide)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xff36615b)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FALL 2026',
                    style: TextStyle(
                      color: Color(0xffc7edd7),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Bắt đầu 07/09/2026',
                    style: TextStyle(color: Color(0xffa4c2bd), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(bottom: 20),
          child: Text(
            'v0.3.3',
            style: TextStyle(color: Color(0xff8bb5ac), fontSize: 11),
          ),
        ),
      ],
    ),
  );

  Widget _heading() {
    final title = [
      'Tổng quan giảng dạy',
      'Lớp học phần',
      'Lịch dạy trong tuần',
      'Cấu hình điểm danh',
    ][_page];
    final description = [
      'Lịch dạy và các lớp của bạn trong học kỳ FALL 2026.',
      'Quản lý danh sách sinh viên theo từng môn và lớp.',
      'Lịch lặp hằng tuần theo tiền tố trong tên sheet Excel.',
      'Thiết lập đăng nhập Google và kết nối dùng chung cho các lớp.',
    ][_page];
    return LayoutBuilder(
      builder: (context, constraints) {
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 6),
            Text(description, style: const TextStyle(color: muted)),
          ],
        );
        if (_page == 3) return copy;
        return constraints.maxWidth < 650
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [copy, const SizedBox(height: 16), _importButton()],
              )
            : Row(
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: 20),
                  _importButton(),
                ],
              );
      },
    );
  }

  Widget _welcome() => Surface(
    child: Column(
      children: [
        EmptyState(
          title: 'Bắt đầu với danh sách lớp của bạn',
          message: 'Chọn file Excel FA26. FAP Helper sẽ đọc từng sheet, nhận diện môn, lớp và lịch học để bạn kiểm tra trước khi lưu.',
          icon: Icons.upload_file_outlined,
          action: _importButton(),
        ),
        const Divider(),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Tên sheet: 11_PRN232_SE1917\nCác cột: Class · RollNumber · Email · MemberCode · FullName',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, height: 1.8),
          ),
        ),
      ],
    ),
  );

  List<Widget> _overview() => [
    LayoutBuilder(
      builder: (context, constraints) {
        final stats = [
          ('${_book!.groups.length}', 'Lớp học phần', Icons.menu_book_outlined),
          (
            '${_book!.subjects.length}',
            'Môn giảng dạy',
            Icons.auto_stories_outlined,
          ),
          ('${_book!.studentCount}', 'Sinh viên', Icons.people_outline),
          (
            '${_book!.enrollmentCount}',
            'Lượt đăng ký học',
            Icons.assignment_ind_outlined,
          ),
        ];
        final columns = constraints.maxWidth >= 780 ? 4 : 2;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: stats
              .map(
                (stat) => SizedBox(
                  width: (constraints.maxWidth - 16 * (columns - 1)) / columns,
                  child: Surface(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                stat.$1,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge,
                              ),
                              Text(
                                stat.$2,
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(stat.$3, color: teal, size: 26),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
    const SizedBox(height: 24),
    _dailySchedule(),
    const SizedBox(height: 28),
    Row(
      children: [
        Expanded(
          child: Text(
            'Các lớp học phần',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        TextButton.icon(
          onPressed: () => setState(() => _page = 1),
          label: const Text('Xem tất cả'),
          icon: const Icon(Icons.arrow_forward, size: 18),
        ),
      ],
    ),
    const SizedBox(height: 12),
    _filters(),
    const SizedBox(height: 20),
    _courseGrid(),
  ];

  Widget _filters({bool search = true}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (search) ...[
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: TextField(
            controller: _search,
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
            decoration: const InputDecoration(
              hintText: 'Tìm mã lớp hoặc mã môn…',
              prefixIcon: Icon(Icons.search, size: 21),
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: Text('Tất cả (${_book!.groups.length})'),
            selected: _subject == null,
            onSelected: (_) => setState(() => _subject = null),
          ),
          for (final subject in _book!.subjects)
            ChoiceChip(
              label: Text(subject),
              selected: _subject == subject,
              onSelected: (_) => setState(
                () => _subject = _subject == subject ? null : subject,
              ),
            ),
        ],
      ),
    ],
  );

  Widget _courseGrid() {
    final groups = _book!.groups
        .where(
          (group) =>
              (_subject == null || group.subjectCode == _subject) &&
              '${group.subjectCode} ${group.classCode}'.toLowerCase().contains(
                _query,
              ),
        )
        .toList();
    if (groups.isEmpty) {
      return const Surface(
        child: EmptyState(
          title: 'Không tìm thấy lớp học phần',
          message: 'Thử từ khóa khác hoặc chọn bộ lọc Tất cả.',
          icon: Icons.search_off,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120
            ? 3
            : constraints.maxWidth >= 650
            ? 2
            : 1;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: groups
              .map(
                (group) => SizedBox(
                  width: (constraints.maxWidth - 16 * (columns - 1)) / columns,
                  child: _courseCard(group),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _courseCard(CourseGroup group) {
    final current = const AttendanceService()
        .onDate(group, _book!.attendanceFor(group.id), _now)
        .any((s) => const AttendanceService().isCurrent(s.session, _now));
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: current ? teal : const Color(0xffe4ebea),
          width: current ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openClass(group),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Tag(group.subjectCode),
                  if (current) const Tag('Đang trong giờ'),
                  const Icon(Icons.north_east, size: 18, color: muted),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                group.classCode,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                '${group.students.length} sinh viên',
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 16,
                    color: muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(group.daysLabel)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.schedule, size: 16, color: muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Slot ${group.slotNumber} · ${group.slot.label}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dailySchedule() {
    final day = _selectedDate ?? calendarDate(_now);
    final today = day == calendarDate(_now);
    final groups = <(CourseGroup, AttendanceSession)>[
      for (final group in _book!.groups)
        for (final entry in const AttendanceService().onDate(
          group,
          _book!.attendanceFor(group.id),
          day,
        ))
          (group, entry.session),
    ]..sort((a, b) => a.$2.slot.compareTo(b.$2.slot));
    return Surface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xffeaf3ef),
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 20,
              runSpacing: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      today ? 'Lịch dạy hôm nay' : 'Lịch dạy theo ngày',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${weekdayLabel(day.weekday)}, ${dateLabel(day)} · ${groups.length} buổi học',
                      style: const TextStyle(color: muted),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Ngày trước',
                      onPressed: () => setState(
                        () => _selectedDate = day.subtract(
                          const Duration(days: 1),
                        ),
                      ),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: day,
                          firstDate: DateTime(day.year - 2, 1, 1),
                          lastDate: DateTime(day.year + 2, 12, 31),
                          helpText: 'Xem lịch dạy',
                        );
                        if (picked != null && mounted) {
                          setState(() => _selectedDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_month, size: 18),
                      label: Text(dateLabel(day)),
                    ),
                    IconButton(
                      tooltip: 'Ngày tiếp',
                      onPressed: () => setState(
                        () => _selectedDate = day.add(const Duration(days: 1)),
                      ),
                      icon: const Icon(Icons.chevron_right),
                    ),
                    if (!today)
                      TextButton(
                        onPressed: () => setState(() => _selectedDate = null),
                        child: const Text('Hôm nay'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (groups.isEmpty)
            EmptyState(
              title: day.isBefore(Markbook.termStart)
                  ? 'Học kỳ chưa bắt đầu'
                  : 'Không có lịch dạy trong ngày',
              message: day.isBefore(Markbook.termStart)
                  ? 'Các lớp bắt đầu học từ 07/09/2026 theo cặp ngày đã quy định.'
                  : 'Bạn có thể chọn ngày khác để xem lịch học của các lớp.',
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in groups)
                    _meetingRow(entry.$1, entry.$2, day, today),
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Text(
              'Lịch theo ngày đã áp dụng tổng số buổi, ngày nghỉ và học bù của từng lớp.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meetingRow(
    CourseGroup group,
    AttendanceSession session,
    DateTime day,
    bool today,
  ) {
    final slot = TeachingSlot.all[session.slot - 1];
    final current = today && const AttendanceService().isCurrent(session, _now);
    final passed =
        calendarDate(day).isBefore(calendarDate(_now)) ||
        (today && _now.hour * 60 + _now.minute >= slot.endMinute);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: current ? paleTeal : const Color(0xfff8faf9),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _openClass(group, date: day, sessionId: session.id),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 24,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 128,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Slot ${session.slot}${session.isMakeup ? ' · Học bù' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        slot.label,
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${group.students.length} sinh viên',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Tag(
                  current
                      ? 'Đang trong giờ'
                      : passed
                      ? 'Đã qua giờ học'
                      : 'Sắp tới',
                  color: current ? teal : muted,
                  background: current
                      ? const Color(0xffd3eddf)
                      : const Color(0xffedf0ef),
                ),
                const Icon(Icons.arrow_forward, color: muted, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _weekSchedule() => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Notice(
          'Đây là lịch tuần gốc từ Excel. Xem Tổng quan theo ngày hoặc mở lớp để thấy lịch đã điều chỉnh ngày nghỉ, học bù và tổng số buổi.',
        ),
        const SizedBox(height: 20),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 1000,
            child: Table(
              border: TableBorder.all(color: const Color(0xffe4ebea)),
              columnWidths: const {0: FixedColumnWidth(136)},
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: Color(0xffedf5f1)),
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Khung giờ',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    for (var weekday = 1; weekday <= 6; weekday++)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          weekdayLabel(weekday),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
                for (final slot in TeachingSlot.all)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Slot ${slot.number}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              slot.label,
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (var weekday = 1; weekday <= 6; weekday++)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 98),
                            child: Column(
                              children: [
                                for (final group in _book!.groups.where(
                                  (group) =>
                                      group.slotNumber == slot.number &&
                                      group.weekdays.contains(weekday) &&
                                      (_subject == null ||
                                          group.subjectCode == _subject),
                                ))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Material(
                                      color: paleTeal,
                                      borderRadius: BorderRadius.circular(8),
                                      child: InkWell(
                                        onTap: () => _openClass(group),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                group.subjectCode,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: teal,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                group.classCode,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                              Text(
                                                '${group.students.length} SV',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: muted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _dataFooter() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(Icons.check_circle_outline, size: 16, color: teal),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'Đã lưu trên máy · ${_book!.sourceName}\nĐiểm danh và tổng số buổi được quản lý riêng trong từng lớp học phần.',
          style: const TextStyle(color: muted, fontSize: 12, height: 1.7),
        ),
      ),
      IconButton(
        tooltip: 'Sao chép đường dẫn dữ liệu',
        icon: const Icon(Icons.folder_copy_outlined, size: 18, color: muted),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: widget.store.file.path));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã sao chép đường dẫn file dữ liệu.'),
            ),
          );
        },
      ),
    ],
  );
}
