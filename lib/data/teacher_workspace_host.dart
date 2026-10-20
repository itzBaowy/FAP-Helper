import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../domain/attendance_models.dart';
import '../domain/attendance_service.dart';
import '../domain/markbook.dart';
import '../domain/session_attendance_report.dart';
import 'attendance_csv.dart';
import 'markbook_workspace.dart';
import 'qr_attendance_host.dart';
import 'qr_collection.dart';

/// Authenticated teacher adapter over the same workspace used by native and QR.
class TeacherWorkspaceHost {
  TeacherWorkspaceHost({
    required this.workspace,
    required this.collection,
    required this.assets,
    this.publicOrigin = '',
    DateTime Function()? now,
  }) : _now = now ?? vietnamNow {
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
          'Địa chỉ web GV phải là origin HTTPS, không kèm đường dẫn hoặc khóa.',
        );
      }
    }
  }
  final MarkbookWorkspace workspace;
  final QrCollection collection;
  final Map<String, String> assets;
  final String publicOrigin;
  final DateTime Function() _now;
  final String accessKey = _newAccessKey();
  static String _newAccessKey() {
    final random = Random.secure();
    return base64Url
        .encode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  static const _service = AttendanceService();
  HttpServer? _server;
  bool _stopped = false;
  int _cachedRevision = -1;
  String? _cachedDay;
  Map<String, Object?> _cached = {};
  String get localOrigin => 'http://localhost:${_server!.port}';
  bool get running => _server != null && !_stopped;

  Future<void> start({int port = 8990}) async {
    if (_server != null || _stopped) {
      throw StateError('Teacher host cannot be restarted.');
    }
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.idleTimeout = const Duration(seconds: 15);
    _server!.listen(_handle);
  }

  Future<void> stop() async {
    _stopped = true;
    await _server?.close(force: true);
  }

  String browserLink({String? apiOrigin}) =>
      '${publicOrigin.isEmpty ? localOrigin : Uri.parse(publicOrigin).origin}/#${Uri(queryParameters: {'api': ?apiOrigin, 'key': accessKey}).query}';

  Map<String, Object?> state({int? revision}) {
    final now = _now();
    if (revision == workspace.revision && _cachedDay == dayKey(now)) {
      return {
        'unchanged': true,
        'revision': workspace.revision,
        'qr': collection.snapshot,
        'serverTime': DateTime.now().toUtc().toIso8601String(),
      };
    }
    if (_cachedRevision != workspace.revision || _cachedDay != dayKey(now)) {
      final book = workspace.book;
      final groups = <Map<String, Object?>>[];
      final sessions = <Map<String, Object?>>[];
      final records = <String, Object?>{};
      if (book != null) {
        for (final group in book.groups) {
          final data = book.attendanceFor(group.id);
          groups.add({
            'id': group.id,
            'subject': group.subjectCode,
            'classCode': group.classCode,
            'sheetName': group.sheetName,
            'dayPair': group.dayPair,
            'slotNumber': group.slotNumber,
            'plannedTotal': data.plannedTotal,
            'requiredTotal': _service.requiredTotal(data),
            'absenceWarningPercent': data.absenceWarningPercent,
            'students': group.students.map((student) {
              final summary = _service.summary(data, student.rollNumber);
              return {
                'roll': student.rollNumber,
                'name': student.fullName,
                'email': student.email,
                'memberCode': student.memberCode,
                'present': summary.present,
                'absent': summary.absent,
                'absencePercent': summary.absencePercent,
              };
            }).toList(),
          });
          for (final scheduled in _service.schedule(
            group,
            data,
            now.add(const Duration(days: 14)),
          )) {
            final session = scheduled.session;
            if (session.state == SessionState.cancelled) continue;
            final id = 'FA26/${group.id}/${session.id}';
            sessions.add({
              'id': id,
              'groupId': group.id,
              'date': dayKey(session.date),
              'slot': session.slot,
              'state': session.state.name,
              'isMakeup': session.isMakeup,
              'canOpen':
                  session.state == SessionState.planned &&
                  _service.hasStarted(session, now),
            });
            if (session.openedAt != null ||
                session.marks.isNotEmpty ||
                session.state == SessionState.closed) {
              final report = SessionAttendanceReport(
                group: group,
                data: data,
                session: session,
              );
              records[id] = {
                'marks': session.marks.map(
                  (roll, mark) => MapEntry(roll, mark.code),
                ),
                'savedAt': data.history
                    .where((e) => e.sessionId == session.id)
                    .lastOrNull
                    ?.at
                    .toUtc()
                    .toIso8601String(),
                'details': {
                  for (final entry in report.entries.where(
                    (e) => e.mark != null,
                  ))
                    entry.student.rollNumber: {
                      'source': entry.source,
                      'at': entry.event?.at.toUtc().toIso8601String(),
                    },
                },
              };
            }
          }
        }
      }
      _cached = {
        'schemaVersion': 1,
        'term': 'FA26',
        'mode': 'windows',
        'revision': workspace.revision,
        'groups': groups,
        'sessions': sessions,
        'records': records,
        'today': dayKey(now),
        'workspaceId': book == null
            ? 'empty'
            : '${book.sourceName}/${book.importedAt.toUtc().toIso8601String()}',
      };
      _cachedRevision = workspace.revision;
      _cachedDay = dayKey(now);
    }
    return {
      ..._cached,
      'qr': collection.snapshot,
      'serverTime': DateTime.now().toUtc().toIso8601String(),
    };
  }

  int _revision(Map<String, dynamic> body) {
    if (body['revision'] is! int) {
      throw const FormatException('Thiếu phiên bản dữ liệu để đối chiếu.');
    }
    return body['revision'] as int;
  }

  ({String group, String session}) _target(Map<String, dynamic> body) {
    final id = body['sessionId'];
    if (id is! String ||
        !RegExp(r'^FA26/[A-Z0-9]+/[A-Z0-9]+/\d{4}-\d{2}-\d{2}/[1-4]$')
            .hasMatch(id)) {
      throw const FormatException('Buổi học không hợp lệ.');
    }
    final parts = id.split('/');
    final group = '${parts[1]}/${parts[2]}',
        session = '${parts[3]}/${parts[4]}';
    final book = workspace.requireBook;
    final course = book.groups.where((g) => g.id == group).firstOrNull;
    if (course == null ||
        !_service
            .schedule(
              course,
              book.attendanceFor(group),
              _now().add(const Duration(days: 14)),
            )
            .any(
              (s) =>
                  s.session.id == session &&
                  s.session.state != SessionState.cancelled,
            )) {
      throw const FormatException('Buổi học không thuộc lịch của lớp.');
    }
    return (group: group, session: session);
  }

  Future<void> _submit(Map<String, dynamic> body) async {
    final target = _target(body);
    final marks = body['marks'];
    final group = workspace.requireBook.groups.firstWhere(
      (g) => g.id == target.group,
    );
    if (marks is! Map<String, dynamic> ||
        marks.length != group.students.length ||
        group.students.any(
          (s) =>
              !marks.containsKey(s.rollNumber) ||
              !['', 'P', 'A', null].contains(marks[s.rollNumber]),
        )) {
      throw const FormatException(
        'Danh sách MSSV hoặc kết quả điểm danh không khớp lớp.',
      );
    }
    final reason = body['reason'] ?? '';
    if (reason is! String || reason.length > 1000) {
      throw const FormatException('Lý do sửa không hợp lệ.');
    }
    await workspace.change((current) {
      var next = current;
      final session = current
          .attendanceFor(target.group)
          .sessions
          .where((s) => s.id == target.session)
          .firstOrNull;
      if (session == null ||
          ![SessionState.open, SessionState.closed].contains(session.state)) {
        throw const FormatException('Mở buổi trước khi lưu điểm danh.');
      }
      for (final student in group.students) {
        final value = marks[student.rollNumber];
        final mark = value == null || value == ''
            ? null
            : parseMark(value as String);
        if (session.marks[student.rollNumber] == mark) continue;
        next = _service.mark(
          next,
          target.group,
          target.session,
          student.rollNumber,
          mark,
          _now(),
          reason: reason,
        );
      }
      return next;
    }, expectedRevision: _revision(body));
  }

  Future<void> _action(Map<String, dynamic> body) async {
    final revision = _revision(body);
    if (revision != workspace.revision) throw const WorkspaceConflict();
    final action = body['action'];
    if (action == 'set-total' || action == 'set-warning') {
      final group = body['groupId'], value = body['value'];
      if (group is! String || (value != null && value is! int)) {
        throw const FormatException('Cấu hình lớp không hợp lệ.');
      }
      await workspace.change(
        (book) => action == 'set-total'
            ? _service.setTotal(book, group, value as int?, _now())
            : _service.setWarningThreshold(book, group, value as int?, _now()),
        expectedRevision: revision,
      );
      return;
    }
    final target = _target(body);
    switch (action) {
      case 'open':
        await workspace.change(
          (book) => _service.open(book, target.group, target.session, _now()),
          expectedRevision: revision,
        );
      case 'close':
        if (collection.active &&
            collection.host!.groupId == target.group &&
            collection.host!.sessionId == target.session) {
          await collection.finalize();
        } else {
          await workspace.change(
            (book) =>
                _service.close(book, target.group, target.session, _now()),
            expectedRevision: revision,
          );
        }
      case 'start-qr':
        if (body['requireSecret'] != null && body['requireSecret'] is! bool) {
          throw const FormatException('Tùy chọn mã bí mật không hợp lệ.');
        }
        await collection.start(
          groupId: target.group,
          sessionId: target.session,
          requireSecret: body['requireSecret'] == true,
        );
      case 'stop-qr':
        if (collection.busy) {
          throw const FormatException(
            'Đang thay đổi kết nối QR. Hãy chờ hoàn tất.',
          );
        }
        if (collection.host != null &&
            (collection.host!.groupId != target.group ||
                collection.host!.sessionId != target.session)) {
          throw const FormatException('Đợt QR đang nhận thuộc một buổi khác.');
        }
        await collection.stop();
      default:
        throw const FormatException('Thao tác không được hỗ trợ.');
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.headers.set(
      'Content-Security-Policy',
      "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self' https://*.trycloudflare.com; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
    );
    void reply(int status, Object? value) {
      response.statusCode = status;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(value));
    }

    try {
      final path = request.uri.path;
      if (request.method == 'GET' && assets.containsKey(path)) {
        response.headers.contentType = ContentType(
          'text',
          path.endsWith('.css')
              ? 'css'
              : path.endsWith('.mjs') || path.endsWith('.js')
              ? 'javascript'
              : 'html',
          charset: 'utf-8',
        );
        response.write(assets[path]);
        return;
      }
      const routes = {
        '/api/state',
        '/api/import',
        '/api/submit',
        '/api/action',
        '/api/export',
        '/api/history',
      };
      if (!routes.contains(path)) {
        reply(404, {'error': 'Không tìm thấy.'});
        return;
      }
      final origin = request.headers.value('origin');
      final local =
          origin == localOrigin ||
          origin == localOrigin.replaceFirst('localhost', '127.0.0.1') ||
          (origin == null &&
              [
                'localhost:${_server!.port}',
                '127.0.0.1:${_server!.port}',
              ].contains(request.headers.value(HttpHeaders.hostHeader)) &&
              request.headers.value('sec-fetch-site') != 'cross-site');
      final remote =
          publicOrigin.isNotEmpty && origin == Uri.parse(publicOrigin).origin;
      if (!local && !remote) {
        reply(403, {'error': 'Origin không được phép kết nối máy GV.'});
        return;
      }
      if (origin != null) {
        response.headers.set('Access-Control-Allow-Origin', origin);
        response.headers.set('Vary', 'Origin');
      }
      if (request.method == 'OPTIONS') {
        final method = request.headers.value('access-control-request-method');
        final headers =
            (request.headers.value('access-control-request-headers') ?? '')
                .toLowerCase()
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty);
        if (!['GET', 'POST'].contains(method) ||
            headers.any(
              (s) => !['authorization', 'content-type'].contains(s),
            )) {
          reply(403, {'error': 'Yêu cầu kết nối không được hỗ trợ.'});
          return;
        }
        response.headers.set(
          'Access-Control-Allow-Methods',
          'GET, POST, OPTIONS',
        );
        response.headers.set(
          'Access-Control-Allow-Headers',
          'Authorization, Content-Type',
        );
        response.statusCode = 204;
        return;
      }
      if (_stopped ||
          request.headers.value('authorization') != 'Bearer $accessKey') {
        reply(401, {
          'error':
              'Khóa kết nối đã hết hiệu lực. Mở lại liên kết trên app Windows.',
        });
        return;
      }
      if (request.method == 'GET' && path == '/api/state') {
        final revision = request.uri.queryParameters['revision'];
        if (revision != null && int.tryParse(revision) == null) {
          throw const FormatException('Phiên bản dữ liệu không hợp lệ.');
        }
        reply(
          200,
          state(revision: revision == null ? null : int.parse(revision)),
        );
        return;
      }
      if (request.method == 'GET' && path == '/api/export') {
        final target = _target({
          'sessionId': request.uri.queryParameters['sessionId'],
        });
        final csv = AttendanceCsv().generate(
          workspace.requireBook,
          target.group,
          DateTime.now(),
          sessionId: target.session,
        );
        response.headers.contentType = ContentType(
          'text',
          'csv',
          charset: 'utf-8',
        );
        response.headers.set(
          'Content-Disposition',
          'attachment; filename="FA26_attendance.csv"',
        );
        response.write(csv);
        return;
      }
      if (request.method == 'GET' && path == '/api/history') {
        final groupId = request.uri.queryParameters['groupId'],
            roll = request.uri.queryParameters['roll'];
        final book = workspace.requireBook;
        final group = book.groups.where((g) => g.id == groupId).firstOrNull;
        if (group == null || !group.students.any((s) => s.rollNumber == roll)) {
          throw const FormatException('Sinh viên không thuộc lớp.');
        }
        final history = book.attendanceFor(group.id).history;
        final before = request.uri.queryParameters['before'];
        final cursor = before == null ? history.length : int.tryParse(before);
        if (cursor == null || cursor < 0 || cursor > history.length) {
          throw const FormatException('Mốc lịch sử không hợp lệ.');
        }
        final events = <Map<String, Object?>>[];
        var index = cursor - 1;
        for (; index >= 0 && events.length < 100; index--) {
          if (history[index].rollNumber == roll) {
            events.add(history[index].toJson());
          }
        }
        reply(200, {
          'events': events,
          'nextCursor': index < 0 ? null : index + 1,
        });
        return;
      }
      if (request.method != 'POST' ||
          !['/api/import', '/api/submit', '/api/action'].contains(path)) {
        reply(405, {'error': 'Phương thức không được hỗ trợ.'});
        return;
      }
      if (request.headers.contentType?.mimeType != 'application/json') {
        reply(415, {'error': 'Yêu cầu cần JSON.'});
        return;
      }
      const limit = 64 * 1024 * 1024;
      if (request.contentLength > limit) {
        reply(413, {'error': 'Dữ liệu vượt quá 64 MB.'});
        return;
      }
      final bytes = <int>[];
      await for (final chunk in request.timeout(const Duration(seconds: 10))) {
        bytes.addAll(chunk);
        if (bytes.length > limit) {
          reply(413, {'error': 'Dữ liệu vượt quá 64 MB.'});
          return;
        }
      }
      final body = jsonDecode(utf8.decode(bytes));
      if (body is! Map<String, dynamic>) {
        throw const FormatException('Nội dung yêu cầu không hợp lệ.');
      }
      if (path == '/api/import') {
        if (collection.active || collection.busy) {
          throw const FormatException(
            'Dừng nhận QR trước khi import danh sách lớp.',
          );
        }
        final revision = _revision(body);
        if (revision != workspace.revision) throw const WorkspaceConflict();
        if (body['book'] is! Map<String, dynamic>) {
          throw const FormatException('Thiếu dữ liệu import.');
        }
        final imported = Markbook.fromJson(
          body['book'] as Map<String, dynamic>,
        );
        final current = workspace.book;
        await workspace.replace(
          current?.mergeImport(imported) ?? imported,
          expected: current,
        );
      } else if (path == '/api/submit') {
        await _submit(body);
      } else {
        await _action(body);
      }
      reply(200, state());
    } on WorkspaceConflict catch (failure) {
      reply(409, {'error': failure.message});
    } on QrRequestError catch (failure) {
      reply(failure.status, {'error': failure.message});
    } on FormatException catch (failure) {
      reply(400, {'error': failure.message});
    } on FileSystemException {
      reply(503, {
        'error': 'Chưa lưu được dữ liệu trên máy GV. Kiểm tra dung lượng và quyền ghi, rồi thử lại.',
      });
    } catch (_) {
      reply(500, {
        'error': 'Chưa hoàn tất thao tác trên máy GV. Hãy kiểm tra kết nối và thử lại.',
      });
    } finally {
      await response.close();
    }
  }
}
