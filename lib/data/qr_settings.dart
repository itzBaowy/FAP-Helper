import 'dart:convert';
import 'dart:io';

import 'markbook_store.dart';

class QrSettings {
  const QrSettings({
    this.clientId = '',
    this.domains = const {'gmail.com', 'fpt.edu.vn'},
    this.publicOrigin = '',
    this.connection = 'quick',
  });
  final String clientId;
  final Set<String> domains;
  final String publicOrigin;
  final String connection;

  void validate({bool requireClient = true}) {
    if (!['quick', 'fixed', 'local', 'vercel'].contains(connection)) {
      throw const FormatException('Chọn cách kết nối trang sinh viên.');
    }
    if (connection == 'vercel' && publicOrigin.isEmpty) {
      throw const FormatException(
        'Nhập địa chỉ production của trang sinh viên trên Vercel.',
      );
    }
    if (connection == 'fixed' && publicOrigin.isEmpty) {
      throw const FormatException(
        'Nhập địa chỉ HTTPS cố định đã chuyển tiếp tới localhost:8787.',
      );
    }
    if ((requireClient || clientId.isNotEmpty) &&
        !RegExp(r'^[a-zA-Z0-9_-]+\.apps\.googleusercontent\.com$')
            .hasMatch(clientId)) {
      throw const FormatException(
        'Nhập OAuth Client ID loại Web application do Google cấp.',
      );
    }
    if (domains.isEmpty ||
        domains.any(
          (d) =>
              !RegExp(r'^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\.[a-z]{2,}$')
                  .hasMatch(d),
        )) {
      throw const FormatException(
        'Nhập miền email, ví dụ gmail.com, fpt.edu.vn.',
      );
    }
    if (publicOrigin.isNotEmpty) {
      final uri = Uri.tryParse(publicOrigin);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          (uri.path.isNotEmpty && uri.path != '/')) {
        throw const FormatException(
          'Địa chỉ Internet phải là HTTPS, chỉ gồm tên miền và cổng nếu có.',
        );
      }
    }
  }

  static File get file => File(
    '${MarkbookStore.forWindows().directory.path}${Platform.pathSeparator}qr-settings.json',
  );
  static Future<QrSettings> load({File? source}) async {
    final target = source ?? file;
    if (!await target.exists()) return const QrSettings();
    final json =
        jsonDecode(await target.readAsString()) as Map<String, dynamic>;
    final settings = QrSettings(
      clientId: json['clientId'] as String,
      domains: Set<String>.from(json['domains'] as List),
      publicOrigin: json['publicOrigin'] as String,
      connection:
          json['connection'] as String? ??
          ((json['publicOrigin'] as String).isEmpty ? 'quick' : 'fixed'),
    );
    settings.validate(requireClient: false);
    return settings;
  }

  Future<void> save({File? target}) async {
    validate(requireClient: false);
    final destination = target ?? file;
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'clientId': clientId,
        'domains': domains.toList(),
        'publicOrigin': publicOrigin,
        'connection': connection,
      }),
      flush: true,
    );
    await temporary.rename(destination.path);
  }
}
