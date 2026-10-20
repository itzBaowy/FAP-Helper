import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/google_identity.dart';
import '../data/qr_attendance_host.dart';
import '../data/qr_settings.dart';
import '../data/qr_collection.dart';
import '../domain/attendance_models.dart';
import '../domain/markbook.dart';
import 'widgets.dart';
import 'session_attendance_panel.dart';

class QrAttendanceDialog extends StatefulWidget {
  const QrAttendanceDialog({
    super.key,
    required this.groupId,
    required this.sessionId,
    required this.readBook,
    required this.onSave,
    this.loadSettings,
    this.createVerifier,
    this.collection,
  });
  final String groupId;
  final String sessionId;
  final Markbook Function() readBook;
  final Future<void> Function(Markbook) onSave;
  final Future<QrSettings> Function()? loadSettings;
  final IdentityVerifier Function(QrSettings)? createVerifier;
  final QrCollection? collection;
  @override
  State<QrAttendanceDialog> createState() => _QrAttendanceDialogState();
}

class _QrAttendanceDialogState extends State<QrAttendanceDialog> {
  QrSettings? _settings;
  String get _connection =>
      _collection.settings?.connection ?? _settings?.connection ?? 'quick';
  bool _secret = false;
  bool _showRoster = true;
  bool _busy = true;
  String? _error;
  String? get _origin => _host == null ? null : _collection.studentOrigin;
  QrAttendanceHost? get _host {
    final host = _collection.host;
    return host?.groupId == widget.groupId &&
            host?.sessionId == widget.sessionId
        ? host
        : null;
  }

  late final QrCollection _collection =
      widget.collection ??
      QrCollection(
        readBook: widget.readBook,
        saveBook: widget.onSave,
        loadSettings: widget.loadSettings,
        createVerifier: widget.createVerifier,
        loadAssets: () async {
          final pages = await Future.wait(
            [
              'index.html',
              'app.js',
              'style.css',
            ].map((name) => rootBundle.loadString('assets/student/$name')),
          );
          return {'/': pages[0], '/app.js': pages[1], '/style.css': pages[2]};
        },
      );
  Timer? _timer;
  bool get _closed => _host != null && _collection.closed;
  bool get _working => _busy || _collection.busy;
  bool get _active => _host?.accepting ?? false;

  @override
  void initState() {
    super.initState();
    _collection.addListener(_collectionChanged);
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _collectionChanged(),
    );
    _load();
  }

  void _collectionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final settings = await (widget.loadSettings ?? QrSettings.load)();
      if (!mounted) return;
      _settings = settings;
    } catch (_) {
      _error = 'Chưa đọc được cấu hình QR. Vào Cấu hình ở sidebar để kiểm tra và lưu lại.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(
      () => _error = error is FormatException
          ? error.message
          : error is QrRequestError
          ? error.message
          : 'Chưa hoàn tất thao tác. Kiểm tra kết nối Internet và quyền ghi file, rồi thử lại.',
    );
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_settings == null || _settings!.clientId.isEmpty) {
        throw const FormatException(
          'Vào Cấu hình ở sidebar để nhập Google Client ID trước khi điểm danh QR.',
        );
      }
      await _collection.start(
        groupId: widget.groupId,
        sessionId: widget.sessionId,
        requireSecret: _secret,
        configuration: _settings,
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    final expectedHost = _host;
    final count = widget
        .readBook()
        .groups
        .firstWhere((g) => g.id == widget.groupId)
        .students
        .length;
    final session = widget
        .readBook()
        .attendanceFor(widget.groupId)
        .sessions
        .firstWhere((s) => s.id == widget.sessionId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chốt danh sách và dừng QR?'),
        content: Text(
          '${count - session.marks.length} ô chưa ghi nhận sẽ chuyển A. Các yêu cầu đến sau khi xác nhận sẽ bị từ chối.',
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (expectedHost == null || !identical(_host, expectedHost)) {
        throw const FormatException(
          'Đợt QR đã thay đổi trên giao diện khác. Kiểm tra lại buổi trước khi chốt.',
        );
      }
      await _collection.finalize();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    setState(() => _busy = true);
    if (_host != null) await _collection.stop();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _collection.removeListener(_collectionChanged);
    if (widget.collection == null) _collection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.readBook().groups.firstWhere(
      (g) => g.id == widget.groupId,
    );
    final session = widget
        .readBook()
        .attendanceFor(widget.groupId)
        .sessions
        .firstWhere((s) => s.id == widget.sessionId);
    final present = session.marks.values
        .where((m) => m == AttendanceMark.present)
        .length;
    final absent = session.marks.values
        .where((m) => m == AttendanceMark.absent)
        .length;
    final error = _error ?? _collection.error;
    return PopScope(
      canPop: false,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1160, maxHeight: 860),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Điểm danh QR · ${group.label}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  '${dateLabel(session.date)} · Slot ${session.slot} · $present/${group.students.length} đã có mặt · $absent vắng · ${group.students.length - session.marks.length} chưa ghi nhận',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 12),
                if (_working) const LinearProgressIndicator(),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      error,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        SwitchListTile(
                          key: const ValueKey('show-qr-roster'),
                          contentPadding: EdgeInsets.zero,
                          value: _showRoster,
                          onChanged: (value) =>
                              setState(() => _showRoster = value),
                          title: const Text('Hiển thị người đã điểm danh'),
                          subtitle: const Text(
                            'Tắt khi trình chiếu để ẩn danh sách sinh viên.',
                          ),
                        ),
                        LayoutBuilder(
                          builder: (context, bounds) {
                            final presentation = _origin == null
                                ? _configuration()
                                : _presentation();
                            if (!_showRoster) return presentation;
                            final roster = SessionAttendancePanel(
                              group: group,
                              data: widget.readBook().attendanceFor(
                                widget.groupId,
                              ),
                              session: session,
                            );
                            if (bounds.maxWidth >= 880) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: presentation),
                                  const SizedBox(width: 24),
                                  Expanded(child: roster),
                                ],
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                presentation,
                                const SizedBox(height: 16),
                                roster,
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (_origin == null) ...[
                      FilledButton.icon(
                        onPressed: _working ? null : _start,
                        icon: const Icon(Icons.qr_code),
                        label: const Text('Bắt đầu nhận QR'),
                      ),
                    ],
                    if (_origin != null && !_closed)
                      FilledButton.icon(
                        onPressed: _working ? null : _finish,
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Chốt danh sách'),
                      ),
                    TextButton(
                      onPressed: _working ? null : _leave,
                      child: Text(
                        _origin != null && !_closed
                            ? 'Dừng nhận QR và quay lại'
                            : 'Quay lại bảng điểm danh',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _configuration() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      const Text(
        'Quét mã → đăng nhập Google → xác nhận có mặt',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      const Text(
        'Client ID, miền email và kết nối được lấy từ mục Cấu hình ở sidebar.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 12),
      const Text(
        'QR đổi mỗi 15 giây. Sinh viên đã quét hợp lệ có 3 phút để đăng nhập và xác nhận; đổi QR không ngắt lượt đã quét. Người chưa quét được phải dùng mã mới.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 20),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _secret,
        onChanged: _busy ? null : (value) => setState(() => _secret = value),
        title: const Text('QR + mã bí mật'),
        subtitle: const Text(
          'Mã 6 chữ số riêng cho đợt nhận điểm danh; QR vẫn đổi mỗi 15 giây.',
        ),
      ),
      const Text(
        'Giữ app và màn hình QR mở trong lúc nhận điểm danh. Chốt danh sách hoặc dừng nhận sẽ vô hiệu hóa mọi lượt quét chưa gửi.',
        style: TextStyle(color: muted, fontSize: 13),
      ),
    ],
  );

  Widget _presentation() {
    if (!_active) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Column(
            children: [
              const Icon(Icons.check_circle_outline, size: 64, color: teal),
              const SizedBox(height: 16),
              Text(
                _closed ? 'Đã chốt danh sách' : 'Đã dừng nhận QR',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 10),
              const Text(
                'Kết quả đã lưu vẫn giữ nguyên. Quay lại bảng điểm danh để kiểm tra hoặc xuất CSV.',
              ),
            ],
          ),
        ),
      );
    }
    final url = _host!.qrUrl;
    final seconds = _host!.qrExpires.difference(DateTime.now()).inMilliseconds;
    return Column(
      children: [
        const SizedBox(height: 12),
        const Text(
          'Quét mã → đăng nhập Google → xác nhận có mặt',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        QrImageView(
          data: url,
          version: QrVersions.auto,
          size: 280,
          backgroundColor: Colors.white,
          semanticsLabel: 'Mã QR điểm danh cho lớp đang chọn',
        ),
        Text(
          'Đổi QR sau ${(seconds / 1000).ceil().clamp(0, 15)} giây',
          style: const TextStyle(color: teal, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Đã quét hợp lệ: tiếp tục trong 3 phút.\nChưa quét được: mã cũ hết hạn, hãy quét mã mới.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 13),
        ),
        if (_collection.requireSecret) ...[
          const SizedBox(height: 10),
          const Text('MÃ BÍ MẬT'),
          SelectableText(
            _host!.secret,
            style: const TextStyle(
              fontSize: 36,
              letterSpacing: 8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          _connection == 'local'
              ? 'Chế độ thử trên máy giảng viên; QR này chưa dùng được bằng điện thoại.'
              : 'Sinh viên có thể dùng Wi-Fi riêng hoặc 4G.',
          style: const TextStyle(color: muted),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => Clipboard.setData(ClipboardData(text: url)),
          icon: const Icon(Icons.copy),
          label: const Text('Sao chép liên kết QR hiện tại'),
        ),
        const Divider(),
        const Text(
          'Google Authorized JavaScript origins',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        SelectableText(_origin!),
        const Text(
          'Nếu Google báo origin_mismatch, thêm đúng địa chỉ trên vào OAuth Client rồi quét lại QR.',
          style: TextStyle(color: muted, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
