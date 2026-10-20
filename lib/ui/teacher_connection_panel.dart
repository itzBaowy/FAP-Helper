import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/teacher_connection.dart';
import 'widgets.dart';

class TeacherConnectionPanel extends StatefulWidget {
  const TeacherConnectionPanel({super.key, required this.connection});
  final TeacherConnection connection;
  @override
  State<TeacherConnectionPanel> createState() => _TeacherConnectionPanelState();
}

class _TeacherConnectionPanelState extends State<TeacherConnectionPanel> {
  late final _origin = TextEditingController(
    text: widget.connection.publicOrigin.isEmpty
        ? 'https://fap-helper-lecturer.vercel.app'
        : widget.connection.publicOrigin,
  );
  late bool _internet = widget.connection.publicOrigin.isNotEmpty;
  @override
  void dispose() {
    _origin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.connection,
    builder: (context, _) {
      final connection = widget.connection;
      return Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Web giảng viên · cùng dữ liệu Windows',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Chọn lớp, nhận QR, sửa và chốt trên web. Dữ liệu được lưu vào cùng file của app; giữ máy Windows và kết nối mở trong buổi học.',
            ),
            Material(
              color: Colors.transparent,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _internet,
                onChanged: connection.connected || connection.busy
                    ? null
                    : (value) => setState(() => _internet = value),
                title: const Text('Kết nối từ Internet'),
                subtitle: Text(
                  _internet
                      ? 'Web GV cần được triển khai bản mới tại địa chỉ HTTPS bên dưới.'
                      : 'Dùng trình duyệt trên cùng máy giảng viên.',
                ),
              ),
            ),
            if (_internet) ...[
              TextField(
                controller: _origin,
                enabled: !connection.connected && !connection.busy,
                decoration: const InputDecoration(
                  labelText: 'Địa chỉ web GV HTTPS',
                  hintText: 'https://ten-project.vercel.app',
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              connection.busy
                  ? 'Đang tạo kết nối…'
                  : connection.connected
                  ? 'Đã kết nối máy Windows'
                  : 'Chưa kết nối',
              style: TextStyle(
                color: connection.connected ? teal : muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (connection.busy) const LinearProgressIndicator(),
            if (connection.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Notice(connection.error!, error: true),
              ),
            if (connection.browserUrl != null) ...[
              const SizedBox(height: 10),
              const Text(
                'Liên kết riêng của giảng viên. Không đưa lên màn hình QR hoặc gửi cho sinh viên.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
              SelectableText(
                connection.browserUrl!,
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (!connection.connected)
                  FilledButton.icon(
                    key: const ValueKey('connect-teacher-web'),
                    onPressed: connection.busy
                        ? null
                        : () => connection.connect(
                            origin: _internet ? _origin.text.trim() : '',
                          ),
                    icon: const Icon(Icons.link),
                    label: const Text('Kết nối web GV'),
                  ),
                if (connection.browserUrl != null)
                  OutlinedButton.icon(
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: connection.browserUrl!),
                    ),
                    icon: const Icon(Icons.copy),
                    label: const Text('Sao chép liên kết mở web'),
                  ),
                if (connection.connected)
                  TextButton(
                    onPressed: connection.busy ? null : connection.disconnect,
                    child: const Text('Ngắt kết nối web'),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
