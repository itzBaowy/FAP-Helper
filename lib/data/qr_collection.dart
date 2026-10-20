import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:qr/qr.dart';

import '../domain/attendance_models.dart';
import '../domain/markbook.dart';
import 'google_identity.dart';
import 'qr_attendance_host.dart';
import 'qr_settings.dart';
import 'quick_tunnel.dart';

/// One collection shared by the native QR dialog and authenticated teacher web.
class QrCollection extends ChangeNotifier {
  QrCollection({
    required this.readBook,
    required this.saveBook,
    required this.loadAssets,
    this.loadSettings,
    this.createVerifier,
    this.port = 8787,
  });
  final Markbook Function() readBook;
  final Future<void> Function(Markbook) saveBook;
  final Future<Map<String, String>> Function() loadAssets;
  final Future<QrSettings> Function()? loadSettings;
  final IdentityVerifier Function(QrSettings)? createVerifier;
  final int port;
  QrAttendanceHost? host;
  QuickTunnel? _tunnel;
  QrSettings? settings;
  String? studentOrigin;
  String? error;
  bool busy = false;
  bool _disposed = false;
  Timer? _cleanup;
  String? _svgUrl;
  String? _svg;
  bool get active => host?.accepting ?? false;
  bool get requireSecret => host?.requireSecret ?? false;
  bool get closed =>
      host != null &&
      readBook()
          .attendanceFor(host!.groupId)
          .sessions
          .any(
            (s) => s.id == host!.sessionId && s.state == SessionState.closed,
          );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Map<String, Object?> get snapshot {
    final url = active ? host!.qrUrl : null;
    if (url != null && url != _svgUrl) {
      final image = QrImage(
        QrCode.fromData(data: url, errorCorrectLevel: QrErrorCorrectLevel.M),
      );
      final path = StringBuffer();
      for (var row = 0; row < image.moduleCount; row++) {
        for (var column = 0; column < image.moduleCount; column++) {
          if (image.isDark(row, column)) {
            path.write('M${column + 4},${row + 4}h1v1h-1z');
          }
        }
      }
      final size = image.moduleCount + 8;
      _svg =
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size" shape-rendering="crispEdges"><rect width="$size" height="$size" fill="white"/><path d="$path" fill="black"/></svg>';
      _svgUrl = url;
    }
    return {
      'active': active,
      'busy': busy,
      'error': error,
      if (host != null) ...{
        'groupId': host!.groupId,
        'sessionId': host!.sessionId,
        ...host!.progress,
      },
      if (active) ...{
        'url': url,
        'svg': _svg,
        'expiresAt': host!.qrExpires.toUtc().toIso8601String(),
        'requiresSecret': requireSecret,
        if (requireSecret) 'secret': host!.secret,
      },
    };
  }

  Future<void> start({
    required String groupId,
    required String sessionId,
    bool requireSecret = false,
    QrSettings? configuration,
  }) async {
    if (_disposed) throw StateError('Collection is closed.');
    if (busy) {
      throw const FormatException(
        'Đang thay đổi kết nối QR. Hãy chờ hoàn tất.',
      );
    }
    if (active) {
      if (host!.groupId == groupId && host!.sessionId == sessionId) return;
      throw const FormatException(
        'Hãy dừng nhận QR của lớp đang mở trước khi chuyển buổi.',
      );
    }
    busy = true;
    error = null;
    _notify();
    QrAttendanceHost? next;
    try {
      await host?.stop();
      _cleanup?.cancel();
      _tunnel?.stop();
      host = null;
      studentOrigin = null;
      final config = configuration ?? await (loadSettings ?? QrSettings.load)();
      config.validate();
      settings = config;
      next = QrAttendanceHost(
        groupId: groupId,
        sessionId: sessionId,
        clientId: config.clientId,
        requireSecret: requireSecret,
        verifier:
            createVerifier?.call(config) ??
            GoogleIdentityVerifier(
              clientId: config.clientId,
              domains: config.domains,
            ),
        readBook: readBook,
        saveBook: (book) async {
          await saveBook(book);
          _notify();
        },
        assets: await loadAssets(),
      );
      host = next;
      await next.start(port: port);
      String origin;
      if (config.connection == 'quick' || config.connection == 'vercel') {
        _tunnel = QuickTunnel(
          onUnexpectedExit: () {
            error = 'Kết nối Internet đã dừng. Kết quả đã lưu vẫn giữ nguyên; hãy mở lại kết nối QR.';
            unawaited(stop());
          },
        );
        origin = await _tunnel!.start(Uri.parse(next.localOrigin).port);
      } else {
        origin = config.connection == 'fixed'
            ? Uri.parse(config.publicOrigin).origin
            : next.localOrigin;
      }
      if (_disposed) {
        await next.stop();
        _tunnel?.stop();
        return;
      }
      studentOrigin = config.connection == 'vercel'
          ? Uri.parse(config.publicOrigin).origin
          : origin;
      next.activate(
        studentOrigin!,
        apiOrigin: config.connection == 'vercel' ? origin : null,
      );
    } catch (failure) {
      await next?.stop();
      _tunnel?.stop();
      host = null;
      rethrow;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> finalize() async {
    if (busy || host == null) {
      throw const FormatException('Chưa có đợt nhận QR sẵn sàng để chốt.');
    }
    busy = true;
    _notify();
    try {
      await host!.finalize();
      await stop();
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> stop({bool immediate = false}) async {
    _cleanup?.cancel();
    host?.deactivate();
    if (immediate) {
      await host?.stop();
      _tunnel?.stop();
    } else {
      // Previously scanned browsers receive an explicit rejection during their
      // original three-minute window, instead of a misleading network failure.
      _cleanup = Timer(
        const Duration(minutes: 3),
        () => unawaited(stop(immediate: true)),
      );
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop(immediate: true));
    super.dispose();
  }
}
