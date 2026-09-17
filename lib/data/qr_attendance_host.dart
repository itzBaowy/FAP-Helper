import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../domain/attendance_models.dart';
import '../domain/attendance_service.dart';
import '../domain/markbook.dart';
import 'google_identity.dart';

class QrRequestError implements Exception {
  const QrRequestError(this.status, this.message);
  final int status;
  final String message;
}

class _ScanTicket {
  _ScanTicket(this.nonce, this.expires);
  final String nonce;
  final DateTime expires;
  Student? student;
  int loginAttempts = 0;
  int secretAttempts = 0;
  bool submitted = false;
}

/// One teacher-controlled QR collection window. No roster/admin/file API is exposed.
/// All mutations, including finalization, share one queue and await durable saving.
class QrAttendanceHost {
  QrAttendanceHost({
    required this.groupId,
    required this.sessionId,
    required this.clientId,
    required this.verifier,
    required this.readBook,
    required this.saveBook,
    required this.assets,
    this.requireSecret = false,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    secret = requireSecret
        ? _random.nextInt(1000000).toString().padLeft(6, '0')
        : '';
  }
  final String groupId;
  final String sessionId;
  final String clientId;
  final IdentityVerifier verifier;
  final Markbook Function() readBook;
  final Future<void> Function(Markbook) saveBook;
  final Map<String, String> assets;
  final bool requireSecret;
  final DateTime Function() _now;
  final _random = Random.secure();
  late final String secret;
  final _tickets = <String, _ScanTicket>{};
  HttpServer? _server;
  String? _origin;
  String? _apiOrigin;
  String _qr = '';
  DateTime? _qrExpires;
  DateTime? _windowExpires;
  Future<void> _tail = Future.value();
  int _pending = 0;
  bool _accepting = false;
  bool _disposed = false;
  String get localOrigin => 'http://localhost:${_server!.port}';
  bool get accepting =>
      _accepting && !_disposed && _now().isBefore(_windowExpires!);
  DateTime get qrExpires {
    currentToken;
    return _qrExpires!;
  }

  String _token() => base64Url
      .encode(List.generate(32, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  Future<void> start({int port = 0}) async {
    if (_disposed || _server != null) {
      throw StateError('Host cannot be started twice.');
    }
    _assertOpen();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.idleTimeout = const Duration(seconds: 15);
    _server!.listen((request) {
      unawaited(_handle(request));
    });
  }

  /// Set only after the HTTPS tunnel is ready (or explicitly testing on this PC).
  void activate(String origin, {String? apiOrigin}) {
    if (_disposed || _server == null || _origin != null) {
      throw StateError('Invalid activation.');
    }
    final uri = Uri.parse(origin);
    if (origin != localOrigin &&
        (uri.scheme != 'https' ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            uri.hasQuery ||
            uri.hasFragment ||
            (uri.path.isNotEmpty && uri.path != '/'))) {
      throw const FormatException('Địa chỉ trang sinh viên không hợp lệ.');
    }
    if (apiOrigin != null &&
        !RegExp(r'^https://[a-z0-9-]+\.trycloudflare\.com$')
            .hasMatch(apiOrigin)) {
      throw const FormatException(
        'Địa chỉ kết nối máy giảng viên không hợp lệ.',
      );
    }
    _origin = uri.origin;
    _apiOrigin = apiOrigin;
    _windowExpires = _now().add(const Duration(hours: 3));
    _accepting = true;
  }

  String get currentToken {
    _assertAccepting();
    if (_qrExpires == null || !_now().isBefore(_qrExpires!)) {
      _qr = _token();
      _qrExpires = _now().add(const Duration(seconds: 15));
    }
    return _qr;
  }

  String get qrUrl => _apiOrigin == null
      ? '$_origin/#$currentToken'
      : '$_origin/#${Uri(queryParameters: {'token': currentToken, 'api': _apiOrigin!}).query}';

  void _assertOpen() {
    final session = readBook()
        .attendanceFor(groupId)
        .sessions
        .where((s) => s.id == sessionId)
        .firstOrNull;
    if (session?.state != SessionState.open) {
      throw const QrRequestError(409, 'Buổi học đã chốt hoặc chưa mở.');
    }
  }

  void _assertAccepting() {
    if (!accepting) {
      throw const QrRequestError(410, 'Giảng viên đã dừng nhận điểm danh.');
    }
    _assertOpen();
  }

  _ScanTicket _ticket(String value) {
    _assertAccepting();
    final ticket = _tickets[value];
    if (ticket == null || !_now().isBefore(ticket.expires)) {
      throw const QrRequestError(
        410,
        'Lượt quét đã hết hạn. Hãy quét QR mới trên màn hình giảng viên.',
      );
    }
    return ticket;
  }

  Map<String, Object?> scan(String qr) {
    _assertAccepting();
    if (qr != currentToken) {
      throw const QrRequestError(410, 'QR đã hết hạn. Hãy quét mã mới.');
    }
    _tickets.removeWhere((_, t) => !_now().isBefore(t.expires));
    if (_tickets.length >= 512) {
      throw const QrRequestError(
        429,
        'Có nhiều lượt quét. Hãy thử lại sau ít phút.',
      );
    }
    final id = _token();
    final ticket = _ScanTicket(
      _token(),
      _now().add(const Duration(minutes: 3)),
    );
    _tickets[id] = ticket;
    final group = readBook().groups.firstWhere((g) => g.id == groupId);
    return {
      'ticket': id,
      'nonce': ticket.nonce,
      'expiresAt': ticket.expires.toUtc().toIso8601String(),
      'clientId': clientId,
      'requiresSecret': requireSecret,
      'classLabel': group.label,
      'sessionLabel': '$sessionId · FA26',
    };
  }

  Future<T> _serial<T>(Future<T> Function() work) {
    if (_pending >= 128) {
      return Future.error(
        const QrRequestError(429, 'Hệ thống đang bận. Hãy thử lại.'),
      );
    }
    _pending++;
    final result = _tail.then((_) => work());
    _tail = result
        .then<void>((_) {}, onError: (Object _, StackTrace _) {})
        .whenComplete(() => _pending--);
    return result;
  }

  Future<Map<String, Object?>> login(
    String id,
    String credential,
  ) => _serial(() async {
    final ticket = _ticket(id);
    if (ticket.student != null) {
      // Retry after a lost HTTP response retains the original authenticated identity.
      return {
        'email': ticket.student!.email,
        'fullName': ticket.student!.fullName,
        'rollNumber': ticket.student!.rollNumber,
      };
    }
    if (++ticket.loginAttempts > 5) {
      throw const QrRequestError(
        429,
        'Đã thử đăng nhập quá nhiều lần. Hãy quét lại.',
      );
    }
    final identity = await verifier.verify(credential, ticket.nonce);
    _ticket(id); // The teacher may have stopped while Google keys were loading.
    final group = readBook().groups.firstWhere((g) => g.id == groupId);
    final student = group.students
        .where((s) => s.email.toLowerCase() == identity.email)
        .firstOrNull;
    if (student == null) {
      throw const QrRequestError(
        403,
        'Email Google không thuộc danh sách lớp này. Hãy chọn đúng tài khoản.',
      );
    }
    ticket.student = student;
    return {
      'email': student.email,
      'fullName': student.fullName,
      'rollNumber': student.rollNumber,
    };
  });

  Future<Map<String, Object?>> submit(
    String id,
    String enteredSecret,
  ) => _serial(() async {
    final ticket = _ticket(id);
    final student = ticket.student;
    if (student == null) {
      throw const QrRequestError(401, 'Hãy đăng nhập Google trước khi gửi.');
    }
    if (ticket.submitted) return {'status': 'P', 'duplicate': true};
    if (requireSecret) {
      if (ticket.secretAttempts >= 5) {
        throw const QrRequestError(
          429,
          'Đã nhập sai mã 5 lần. Hãy quét lại QR.',
        );
      }
      if (enteredSecret != secret) {
        ticket.secretAttempts++;
        throw const QrRequestError(
          400,
          'Mã bí mật không đúng. Hãy nhập lại mã giảng viên cung cấp.',
        );
      }
    }
    final book = readBook();
    final session = book
        .attendanceFor(groupId)
        .sessions
        .firstWhere((s) => s.id == sessionId);
    final previous = session.marks[student.rollNumber];
    // A teacher's explicit A is not silently overwritten by a student request.
    if (previous == AttendanceMark.absent) {
      throw const QrRequestError(
        409,
        'Giảng viên đã ghi A. Hãy liên hệ giảng viên để kiểm tra.',
      );
    }
    final utc = _now().toUtc().add(const Duration(hours: 7));
    final vietnam = DateTime(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
    );
    final next = const AttendanceService().mark(
      book,
      groupId,
      sessionId,
      student.rollNumber,
      AttendanceMark.present,
      vietnam,
      reason: 'Điểm danh QR · Google đã xác thực email',
      fromQr: true,
    );
    if (!identical(book, next)) await saveBook(next);
    ticket.submitted = true;
    return {'status': 'P', 'duplicate': previous == AttendanceMark.present};
  });

  Future<void> finalize() async {
    _accepting = false;
    // Always enqueue finalization, even when the request queue is full.
    await _tail;
    _assertOpen();
    final utc = _now().toUtc().add(const Duration(hours: 7));
    final vietnam = DateTime(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
    );
    await saveBook(
      const AttendanceService().close(readBook(), groupId, sessionId, vietnam),
    );
  }

  Future<void> stop() async {
    _accepting = false;
    if (_disposed) return;
    _disposed = true;
    await _tail;
    _tickets.clear();
    await _server?.close(force: true);
    verifier.dispose();
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.headers.set(
      'Cross-Origin-Opener-Policy',
      'same-origin-allow-popups',
    );
    response.headers.set(
      'Content-Security-Policy',
      "default-src 'self'; script-src 'self' https://accounts.google.com/gsi/client; style-src 'self' https://accounts.google.com/gsi/style; frame-src https://accounts.google.com/gsi/; connect-src 'self' https://accounts.google.com/gsi/; img-src 'self' data: https://*.googleusercontent.com; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
    );
    try {
      final apiPath = [
        '/api/scan',
        '/api/login',
        '/api/submit',
      ].contains(request.uri.path);
      if (apiPath &&
          (request.method == 'OPTIONS' || request.method == 'POST')) {
        if (_origin == null || request.headers.value('origin') != _origin) {
          throw const QrRequestError(403, 'Nguồn yêu cầu không hợp lệ.');
        }
        response.headers.set('Access-Control-Allow-Origin', _origin!);
        response.headers.set('Vary', 'Origin');
        if (request.method == 'OPTIONS') {
          final headers =
              (request.headers.value('access-control-request-headers') ?? '')
                  .toLowerCase()
                  .split(',')
                  .map((h) => h.trim())
                  .where((h) => h.isNotEmpty);
          if (request.headers.value('access-control-request-method') !=
                  'POST' ||
              headers.any((h) => h != 'content-type')) {
            throw const QrRequestError(
              403,
              'Yêu cầu kết nối không được hỗ trợ.',
            );
          }
          response.headers.set('Access-Control-Allow-Methods', 'POST');
          response.headers.set('Access-Control-Allow-Headers', 'Content-Type');
          response.headers.set('Access-Control-Max-Age', '600');
          response.statusCode = HttpStatus.noContent;
          return;
        }
      }
      if (request.method == 'GET' && assets.containsKey(request.uri.path)) {
        final path = request.uri.path;
        response.headers.contentType = ContentType(
          'text',
          path.endsWith('.js')
              ? 'javascript'
              : path.endsWith('.css')
              ? 'css'
              : 'html',
          charset: 'utf-8',
        );
        response.write(assets[path]);
      } else if (request.method == 'POST' &&
          [
            '/api/scan',
            '/api/login',
            '/api/submit',
          ].contains(request.uri.path)) {
        final origin = request.headers.value('origin');
        if (origin != _origin) {
          throw const QrRequestError(403, 'Nguồn yêu cầu không hợp lệ.');
        }
        if (request.headers.contentType?.mimeType != 'application/json') {
          throw const QrRequestError(415, 'Yêu cầu cần JSON.');
        }
        if (request.contentLength > 16000) {
          throw const QrRequestError(413, 'Yêu cầu quá lớn.');
        }
        final bytes = <int>[];
        await for (final chunk in request.timeout(
          const Duration(seconds: 10),
        )) {
          bytes.addAll(chunk);
          if (bytes.length > 16000) {
            throw const QrRequestError(413, 'Yêu cầu quá lớn.');
          }
        }
        final json = jsonDecode(utf8.decode(bytes));
        if (json is! Map<String, dynamic>) {
          throw const QrRequestError(400, 'Yêu cầu không hợp lệ.');
        }
        String field(String key) {
          final value = json[key];
          if (value is! String) {
            throw const QrRequestError(400, 'Yêu cầu thiếu thông tin.');
          }
          return value;
        }

        final result = switch (request.uri.path) {
          '/api/scan' => scan(field('token')),
          '/api/login' => await login(field('ticket'), field('credential')),
          _ => await submit(field('ticket'), field('secret')),
        };
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode(result));
      } else {
        throw const QrRequestError(404, 'Không tìm thấy trang.');
      }
    } catch (error) {
      response.statusCode = error is QrRequestError
          ? error.status
          : error is FormatException
          ? 400
          : 503;
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode({
          'error': error is QrRequestError
              ? error.message
              : error is FormatException
              ? error.message
              : 'Chưa lưu được điểm danh. Hãy thử lại hoặc báo giảng viên.',
        }),
      );
    } finally {
      try {
        await response.close();
      } catch (_) {
        /* Disconnected phone. */
      }
    }
  }
}
