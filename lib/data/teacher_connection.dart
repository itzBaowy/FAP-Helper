import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'markbook_workspace.dart';
import 'qr_collection.dart';
import 'quick_tunnel.dart';
import 'teacher_workspace_host.dart';

Future<Map<String, String>> loadStudentAssets() async {
  final result = <String, String>{};
  for (final name in ['index.html', 'app.js', 'style.css']) {
    result[name == 'index.html' ? '/' : '/$name'] = await rootBundle.loadString(
      'assets/student/$name',
    );
  }
  return result;
}

Future<Map<String, String>> loadTeacherAssets() async {
  final result = <String, String>{};
  for (final name in [
    'index.html',
    'app.mjs',
    'connection.mjs',
    'xlsx-importer.mjs',
    'style.css',
    'workspace.mjs',
    'reports.mjs',
  ]) {
    result[name == 'index.html' ? '/' : '/$name'] = await rootBundle.loadString(
      'assets/teacher/$name',
    );
  }
  return result;
}

class TeacherConnection extends ChangeNotifier {
  TeacherConnection({
    required this.workspace,
    required this.collection,
    this.loadAssets = loadTeacherAssets,
  });
  final MarkbookWorkspace workspace;
  final QrCollection collection;
  final Future<Map<String, String>> Function() loadAssets;
  TeacherWorkspaceHost? _host;
  QuickTunnel? _tunnel;
  bool _disposed = false;
  bool busy = false;
  String? error;
  String? browserUrl;
  String publicOrigin = '';
  bool get connected => _host?.running ?? false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> connect({String origin = ''}) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    _notify();
    TeacherWorkspaceHost? next;
    try {
      await _host?.stop();
      _tunnel?.stop();
      browserUrl = null;
      next = TeacherWorkspaceHost(
        workspace: workspace,
        collection: collection,
        assets: await loadAssets(),
        publicOrigin: origin,
      );
      _host = next;
      publicOrigin = origin;
      await next.start();
      String? apiOrigin;
      if (origin.isNotEmpty) {
        _tunnel = QuickTunnel(
          onUnexpectedExit: () {
            error = 'Kết nối web GV đã dừng. Điểm danh đã lưu vẫn ở máy Windows; bấm kết nối lại.';
            unawaited(disconnect());
          },
        );
        apiOrigin = await _tunnel!.start(Uri.parse(next.localOrigin).port);
      }
      if (_disposed) {
        await next.stop();
        _tunnel?.stop();
        return;
      }
      browserUrl = next.browserLink(apiOrigin: apiOrigin);
    } catch (failure) {
      await next?.stop();
      _tunnel?.stop();
      _host = null;
      error = failure is FormatException
          ? failure.message
          : failure is SocketException
          ? 'Chưa mở được cổng 8990. Dừng server giả lập đang chạy, rồi kết nối lại.'
          : 'Chưa tạo được kết nối web GV. Kiểm tra Internet, bộ assets và cloudflared.exe trong bản phát hành.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> disconnect() async {
    await _host?.stop();
    _tunnel?.stop();
    _host = null;
    browserUrl = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disconnect());
    super.dispose();
  }
}
