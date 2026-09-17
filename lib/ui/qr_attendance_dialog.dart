import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/google_identity.dart';
import '../data/qr_attendance_host.dart';
import '../data/qr_settings.dart';
import '../data/quick_tunnel.dart';
import '../domain/attendance_models.dart';
import '../domain/markbook.dart';
import 'widgets.dart';

class QrAttendanceDialog extends StatefulWidget {
  const QrAttendanceDialog({
    super.key,
    required this.groupId,
    required this.sessionId,
    required this.readBook,
    required this.onSave,
    this.loadSettings,
  });
  final String groupId;
  final String sessionId;
  final Markbook Function() readBook;
  final Future<void> Function(Markbook) onSave;
  final Future<QrSettings> Function()? loadSettings;
  @override
  State<QrAttendanceDialog> createState() => _QrAttendanceDialogState();
}

class _QrAttendanceDialogState extends State<QrAttendanceDialog> {
  QrSettings? _settings;
  String get _connection => _settings?.connection ?? 'quick';
  bool _secret = false;
  bool _busy = true;
  String? _error;
  String? _origin;
  QrAttendanceHost? _host;
  QuickTunnel? _tunnel;
  Timer? _timer;
  bool _closed = false;
  bool get _active => _host?.accepting ?? false;

  @override
  void initState() {
    super.initState();
    _load();
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
    QrAttendanceHost? host;
    try {
      final settings = _settings;
      if (settings == null || settings.clientId.isEmpty) {
        throw const FormatException(
          'Vào Cấu hình ở sidebar để nhập Google Client ID trước khi điểm danh QR.',
        );
      }
      settings.validate();
      if (_connection == 'fixed' && settings.publicOrigin.isEmpty) {
        throw const FormatException(
          'Nhập địa chỉ HTTPS cố định đã chuyển tiếp tới localhost:8787.',
        );
      }
      final pages = await Future.wait(
        [
          'index.html',
          'app.js',
          'style.css',
        ].map((name) => rootBundle.loadString('assets/student/$name')),
      );
      if (!mounted) return;
      host = QrAttendanceHost(
        groupId: widget.groupId,
        sessionId: widget.sessionId,
        clientId: settings.clientId,
        requireSecret: _secret,
        verifier: GoogleIdentityVerifier(
          clientId: settings.clientId,
          domains: settings.domains,
        ),
        readBook: widget.readBook,
        saveBook: (next) async {
          await widget.onSave(next);
          if (mounted) setState(() {});
        },
        assets: {'/': pages[0], '/app.js': pages[1], '/style.css': pages[2]},
      );
      _host = host;
      await host.start(port: 8787);
      String origin;
      if (_connection == 'quick' || _connection == 'vercel') {
        _tunnel = QuickTunnel(
          onUnexpectedExit: () {
            if (mounted && _origin != null && !_closed) {
              unawaited(_host!.stop());
              _showError(
                const FormatException(
                  'Kết nối Internet đã dừng. Kết quả đã lưu vẫn giữ nguyên; quay lại để mở kết nối mới.',
                ),
              );
            }
          },
        );
        origin = await _tunnel!.start(8787);
      } else {
        origin = _connection == 'fixed'
            ? Uri.parse(settings.publicOrigin).origin
            : host.localOrigin;
      }
      if (!mounted) {
        await host.stop();
        _tunnel?.stop();
        return;
      }
      final studentOrigin = _connection == 'vercel'
          ? Uri.parse(settings.publicOrigin).origin
          : origin;
      host.activate(
        studentOrigin,
        apiOrigin: _connection == 'vercel' ? origin : null,
      );
      _origin = studentOrigin;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } catch (error) {
      await host?.stop();
      _tunnel?.stop();
      _host = null;
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
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
      await _host!.finalize();
      _closed = true;
      await _host!.stop();
      _tunnel?.stop();
      _timer?.cancel();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    setState(() => _busy = true);
    await _host?.stop();
    _tunnel?.stop();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tunnel?.stop();
    if (_host != null) unawaited(_host!.stop());
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
    return PopScope(
      canPop: false,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960, maxHeight: 860),
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
                  '${dateLabel(session.date)} · Slot ${session.slot} · $present/${group.students.length} đã có mặt',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 12),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    child: _origin == null ? _configuration() : _presentation(),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (_origin == null) ...[
                      FilledButton.icon(
                        onPressed: _busy ? null : _start,
                        icon: const Icon(Icons.qr_code),
                        label: const Text('Bắt đầu nhận QR'),
                      ),
                    ],
                    if (_origin != null && !_closed)
                      FilledButton.icon(
                        onPressed: _busy ? null : _finish,
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Chốt danh sách'),
                      ),
                    TextButton(
                      onPressed: _busy ? null : _leave,
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
        if (_secret) ...[
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
