import 'package:flutter/material.dart';

import '../data/qr_settings.dart';
import 'widgets.dart';

class QrSettingsPanel extends StatefulWidget {
  const QrSettingsPanel({
    super.key,
    required this.loadSettings,
    required this.saveSettings,
  });
  final Future<QrSettings> Function() loadSettings;
  final Future<void> Function(QrSettings) saveSettings;
  @override
  State<QrSettingsPanel> createState() => _QrSettingsPanelState();
}

class _QrSettingsPanelState extends State<QrSettingsPanel> {
  final _client = TextEditingController();
  final _domains = TextEditingController(text: 'gmail.com, fpt.edu.vn');
  final _public = TextEditingController();
  String _connection = 'quick';
  bool _busy = true;
  String? _error;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.loadSettings();
      if (!mounted) return;
      _client.text = settings.clientId;
      _domains.text = settings.domains.join(', ');
      _public.text = settings.publicOrigin;
      _connection = settings.connection;
    } catch (_) {
      _error =
          'Chưa đọc được cấu hình. Nhập lại các thông tin bên dưới rồi lưu.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _saved = false;
    });
    try {
      final settings = QrSettings(
        clientId: _client.text.trim(),
        domains: _domains.text
            .split(',')
            .map((d) => d.trim().toLowerCase().replaceFirst(RegExp(r'^@'), ''))
            .where((d) => d.isNotEmpty)
            .toSet(),
        publicOrigin: _public.text.trim(),
        connection: _connection,
      );
      settings.validate(requireClient: false);
      await widget.saveSettings(settings);
      if (mounted) setState(() => _saved = true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'Chưa lưu được cấu hình. Kiểm tra quyền ghi file rồi thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _edited(String _) {
    if (_saved) setState(() => _saved = false);
  }

  @override
  void dispose() {
    _client.dispose();
    _domains.dispose();
    _public.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Notice(_error!, error: true),
            const SizedBox(height: 16),
          ],
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đăng nhập Google',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Dùng chung cho các lớp. Sinh viên phải đăng nhập email có trong danh sách của lớp đang điểm danh.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _client,
                  enabled: !_busy,
                  onChanged: _edited,
                  decoration: const InputDecoration(
                    labelText: 'Google OAuth Client ID · Web application',
                    hintText: '…apps.googleusercontent.com',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _domains,
                  enabled: !_busy,
                  onChanged: _edited,
                  decoration: const InputDecoration(
                    labelText: 'Miền email được phép',
                    helperText:
                        'Ngăn cách bằng dấu phẩy, ví dụ gmail.com, fpt.edu.vn.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kết nối trang sinh viên',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  key: ValueKey(_connection),
                  initialValue: _connection,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Cách kết nối'),
                  items: const [
                    DropdownMenuItem(
                      value: 'vercel',
                      child: Text('Internet · trang sinh viên trên Vercel'),
                    ),
                    DropdownMenuItem(
                      value: 'quick',
                      child: Text('Internet · địa chỉ thử nghiệm Cloudflare'),
                    ),
                    DropdownMenuItem(
                      value: 'fixed',
                      child: Text('Internet · địa chỉ HTTPS cố định'),
                    ),
                    DropdownMenuItem(
                      value: 'local',
                      child: Text('Thử trên máy này · localhost'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                          _connection = value!;
                          _saved = false;
                        }),
                ),
                const SizedBox(height: 12),
                Text(switch (_connection) {
                  'vercel' => 'Dùng địa chỉ production Vercel cố định cho Google đăng nhập. App tự tạo kết nối Cloudflare tới máy giảng viên; không cần thêm địa chỉ Cloudflare vào Google origins.',
                  'local' => 'Chỉ mở được trên máy giảng viên. Điện thoại cần kết nối Internet. Google origins: http://localhost và http://localhost:8787.',
                  'fixed' => 'Tên miền phải chuyển tiếp tới http://127.0.0.1:8787 trên máy này và được thêm vào Google Authorized JavaScript origins.',
                  _ => 'Giảng viên và sinh viên có thể dùng hai mạng khác nhau. Mỗi kết nối tạo địa chỉ HTTPS mới; thêm đúng địa chỉ hiện trên màn hình QR vào Google Authorized JavaScript origins.',
                }, style: const TextStyle(color: muted, fontSize: 13)),
                if (_connection == 'fixed' || _connection == 'vercel') ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _public,
                    enabled: !_busy,
                    onChanged: _edited,
                    decoration: InputDecoration(
                      labelText: _connection == 'vercel'
                          ? 'Địa chỉ production Vercel'
                          : 'Địa chỉ HTTPS cố định',
                      hintText: _connection == 'vercel'
                          ? 'https://ten-du-an.vercel.app'
                          : 'https://diemdanh.example.edu.vn',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Lưu cấu hình'),
              ),
              if (_saved)
                const Text(
                  'Đã lưu. Áp dụng khi mở đợt QR tiếp theo.',
                  style: TextStyle(color: teal),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
