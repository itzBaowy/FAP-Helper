import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fap_helper_v1/data/google_identity.dart';
import 'package:fap_helper_v1/data/markbook_store.dart';
import 'package:fap_helper_v1/data/markbook_workspace.dart';
import 'package:fap_helper_v1/data/qr_collection.dart';
import 'package:fap_helper_v1/data/qr_settings.dart';
import 'package:fap_helper_v1/data/teacher_workspace_host.dart';
import 'package:fap_helper_v1/domain/attendance_models.dart';
import 'package:fap_helper_v1/domain/attendance_service.dart';

import 'support/attendance_fixture.dart';

class _Identity implements IdentityVerifier {
  @override
  Future<GoogleIdentity> verify(String credential, String nonce) async =>
      GoogleIdentity(credential, 'fixture');
  @override
  void dispose() {}
}

void main() {
  const group = 'PRM393/SE1920',
      session = '2026-09-07/1',
      webSession = 'FA26/PRM393/SE1920/2026-09-07/1';
  final now = DateTime(2026, 10, 21, 10);
  late Directory directory;
  late MarkbookWorkspace workspace;
  late QrCollection collection;
  late TeacherWorkspaceHost teacher;
  late HttpClient client;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fap-teacher-http-');
    workspace = MarkbookWorkspace(MarkbookStore(directory));
    await workspace.replace(
      const AttendanceService().open(attendanceFixture(), group, session, now),
      expected: null,
    );
    collection = QrCollection(
      readBook: () => workspace.requireBook,
      saveBook: (next) => workspace.replace(next, expected: workspace.book),
      loadAssets: () async => {'/': '<html>Student fixture</html>'},
      loadSettings: () async => const QrSettings(
        clientId: 'test.apps.googleusercontent.com',
        connection: 'local',
      ),
      createVerifier: (_) => _Identity(),
      port: 0,
    );
    teacher = TeacherWorkspaceHost(
      workspace: workspace,
      collection: collection,
      assets: {'/': '<html>Teacher fixture</html>'},
      publicOrigin: 'https://teacher.example.com',
      now: () => now,
    );
    await teacher.start(port: 0);
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await teacher.stop();
    await collection.stop(immediate: true);
    collection.dispose();
    workspace.dispose();
    await directory.delete(recursive: true);
  });
  Future<(int, String)> request(
    String path, {
    Map<String, Object?>? body,
    bool authorized = true,
    bool sendOrigin = true,
    String? origin,
  }) async {
    final req = await client.openUrl(
      body == null ? 'GET' : 'POST',
      Uri.parse('${teacher.localOrigin}$path'),
    );
    if (sendOrigin) req.headers.set('Origin', origin ?? teacher.localOrigin);
    if (authorized) {
      req.headers.set('Authorization', 'Bearer ${teacher.accessKey}');
    }
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    return (res.statusCode, await utf8.decoder.bind(res).join());
  }

  Future<Map<String, dynamic>> state() async =>
      jsonDecode((await request('/api/state')).$2) as Map<String, dynamic>;

  test(
    'teacher metadata and roster require the key and an exact allowed origin',
    () async {
      expect((await request('/api/state', authorized: false)).$1, 401);
      expect((await request('/api/state', sendOrigin: false)).$1, 200);
      expect(
        (await request('/api/state', origin: 'https://evil.example')).$1,
        403,
      );
      expect((await request('/FA26.json')).$1, 404);
      final response = await request(
        '/api/state',
        origin: 'https://teacher.example.com',
      );
      expect(response.$1, 200);
      expect(response.$2, contains('an@example.com'));
      final revision = workspace.revision;
      final unchanged = jsonDecode(
        (await request('/api/state?revision=$revision')).$2,
      ) as Map;
      expect(unchanged['unchanged'], true);
      expect(unchanged.containsKey('groups'), false);
    },
  );

  test('web QR, student confirmation and native state use one saved Markbook; stale web writes cannot erase P', () async {
    final before = workspace.revision;
    expect(
      (await request(
        '/api/action',
        body: {
          'action': 'start-qr',
          'sessionId': webSession,
          'revision': before,
        },
      )).$1,
      200,
    );
    expect((await state())['qr'], containsPair('active', true));
    expect((collection.snapshot['svg'] as String), contains('<svg'));
    expect(
      (await request(
        '/api/import',
        body: {
          'revision': workspace.revision,
          'book': workspace.requireBook.toJson(),
        },
      )).$1,
      400,
    );
    expect(workspace.revision, before);
    final qr = collection.host!;
    final scan = qr.scan(qr.currentToken), ticket = scan['ticket'] as String;
    expect((await state())['qr'], containsPair('activeScans', 1));
    await qr.login(ticket, 'an@example.com');
    expect((await state())['qr'], containsPair('verifiedStudents', 1));
    await qr.submit(ticket, '');
    expect((await state())['qr'], containsPair('savedPresent', 1));
    final stale = await request(
      '/api/submit',
      body: {
        'sessionId': webSession,
        'revision': before,
        'marks': {'SE000001': '', 'SE000002': 'A', 'SE000003': ''},
      },
    );
    expect(stale.$1, 409);
    expect(
      workspace.requireBook
          .attendanceFor(group)
          .sessions
          .single
          .marks['SE000001'],
      AttendanceMark.present,
    );
    expect(
      (await workspace.store.load()).markbook!
          .attendanceFor(group)
          .sessions
          .single
          .marks['SE000001'],
      AttendanceMark.present,
    );
    final saved = await request(
      '/api/submit',
      body: {
        'sessionId': webSession,
        'revision': workspace.revision,
        'marks': {'SE000001': 'P', 'SE000002': 'A', 'SE000003': ''},
      },
    );
    expect(saved.$1, 200);
    expect(
      (await request(
        '/api/action',
        body: {
          'action': 'close',
          'sessionId': webSession,
          'revision': workspace.revision,
        },
      )).$1,
      200,
    );
    expect(collection.active, false);
    final rejected = await client.postUrl(
      Uri.parse('${qr.localOrigin}/api/resume'),
    );
    rejected.headers.set('Origin', qr.localOrigin);
    rejected.headers.contentType = ContentType.json;
    rejected.write(jsonEncode({'ticket': ticket}));
    final rejection = await rejected.close();
    expect(rejection.statusCode, 410);
    await rejection.drain<void>();
    final closed = workspace.requireBook.attendanceFor(group).sessions.single;
    expect(closed.state, SessionState.closed);
    expect(closed.marks['SE000003'], AttendanceMark.absent);
    final csv = await request(
      '/api/export?sessionId=${Uri.encodeComponent(webSession)}',
    );
    expect(csv.$1, 200);
    expect(csv.$2, contains('"SchemaVersion","Term"'));
    expect(csv.$2, contains('"Nguyễn Văn An"'));
  });

  test('closed corrections require a reason and warning policy persists to the shared file', () async {
    await workspace.change(
      (book) => const AttendanceService().close(book, group, session, now),
    );
    final body = <String, Object?>{
      'sessionId': webSession,
      'revision': workspace.revision,
      'marks': {'SE000001': 'P', 'SE000002': 'A', 'SE000003': 'A'},
    };
    expect((await request('/api/submit', body: body)).$1, 400);
    body['reason'] = 'Xác nhận từ giảng viên';
    expect((await request('/api/submit', body: body)).$1, 200);
    expect(
      workspace.requireBook.attendanceFor(group).history.last.action,
      'correct',
    );
    expect(
      (await request(
        '/api/action',
        body: {
          'action': 'set-total',
          'groupId': group,
          'value': 10,
          'revision': workspace.revision,
        },
      )).$1,
      200,
    );
    expect(
      (await request(
        '/api/action',
        body: {
          'action': 'set-warning',
          'groupId': group,
          'value': 20,
          'revision': workspace.revision,
        },
      )).$1,
      200,
    );
    expect(
      (await workspace.store.load()).markbook!
          .attendanceFor(group)
          .absenceWarningPercent,
      20,
    );
    final history = await request(
      '/api/history?groupId=PRM393%2FSE1920&roll=SE000001',
    );
    expect(history.$1, 200);
    expect(
      (jsonDecode(history.$2)['events'] as List).any(
        (e) => e['action'] == 'correct',
      ),
      true,
    );
    expect(
      (await request('/api/history?groupId=PRM393%2FSE1920&roll=UNKNOWN')).$1,
      400,
    );
  });
}
