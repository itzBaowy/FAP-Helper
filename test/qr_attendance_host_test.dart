import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fap_helper_v1/data/google_identity.dart';
import 'package:fap_helper_v1/data/qr_attendance_host.dart';
import 'package:fap_helper_v1/data/markbook_store.dart';
import 'package:fap_helper_v1/domain/attendance_models.dart';
import 'package:fap_helper_v1/domain/attendance_service.dart';
import 'package:fap_helper_v1/domain/markbook.dart';

import 'support/attendance_fixture.dart';

class TestIdentityVerifier implements IdentityVerifier {
  Future<void> Function()? gate;
  @override
  Future<GoogleIdentity> verify(String credential, String nonce) async {
    await gate?.call();
    if (credential == 'invalid') {
      throw const FormatException('Invalid identity');
    }
    return GoogleIdentity(credential, 'test-user');
  }

  @override
  void dispose() {}
}

void main() {
  const group = 'PRM393/SE1920';
  const session = '2026-09-07/1';
  const service = AttendanceService();
  late Markbook book;
  late QrAttendanceHost host;
  late TestIdentityVerifier verifier;
  late DateTime now;
  Future<void> Function(Markbook)? save;
  var saves = 0;
  Matcher status(int code) =>
      isA<QrRequestError>().having((e) => e.status, 'status', code);
  Future<void> setupHost({
    bool secret = false,
    String? studentOrigin,
    String? apiOrigin,
  }) async {
    host = QrAttendanceHost(
      groupId: group,
      sessionId: session,
      clientId: 'test.apps.googleusercontent.com',
      verifier: verifier,
      readBook: () => book,
      saveBook: (next) async {
        await save?.call(next);
        book = next;
        saves++;
      },
      now: () => now,
      requireSecret: secret,
      assets: {'/': '<html>Test student page</html>'},
    );
    await host.start();
    host.activate(studentOrigin ?? host.localOrigin, apiOrigin: apiOrigin);
  }

  setUp(() {
    book = service.open(
      attendanceFixture(),
      group,
      session,
      DateTime(2026, 9, 7, 8),
    );
    now = DateTime.utc(2026, 9, 7, 1);
    verifier = TestIdentityVerifier();
    save = null;
    saves = 0;
  });
  tearDown(() async => host.stop());
  test(
    'Vercel QR targets stable frontend and permits only its CORS origin',
    () async {
      const frontend = 'https://student-demo.vercel.app';
      const backend = 'https://teacher-demo.trycloudflare.com';
      await setupHost(studentOrigin: frontend, apiOrigin: backend);
      final link = Uri.parse(host.qrUrl);
      expect(link.origin, frontend);
      final payload = Uri.splitQueryString(link.fragment);
      expect(payload['api'], backend);
      expect(payload['token'], host.currentToken);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      Future<HttpClientResponse> preflight(
        String origin, {
        String method = 'POST',
      }) async {
        final request = await client.openUrl(
          'OPTIONS',
          Uri.parse('${host.localOrigin}/api/scan'),
        );
        request.headers.set('Origin', origin);
        request.headers.set('Access-Control-Request-Method', method);
        request.headers.set('Access-Control-Request-Headers', 'content-type');
        return request.close();
      }

      final accepted = await preflight(frontend);
      expect(accepted.statusCode, 204);
      expect(accepted.headers.value('access-control-allow-origin'), frontend);
      expect(
        accepted.headers.value('access-control-allow-credentials'),
        isNull,
      );
      await accepted.drain<void>();
      final rejected = await preflight('https://other.vercel.app');
      expect(rejected.statusCode, 403);
      expect(rejected.headers.value('access-control-allow-origin'), isNull);
      await rejected.drain<void>();
      final wrongMethod = await preflight(frontend, method: 'DELETE');
      expect(wrongMethod.statusCode, 403);
      await wrongMethod.drain<void>();
      final scanRequest = await client.postUrl(
        Uri.parse('${host.localOrigin}/api/scan'),
      );
      scanRequest.headers.set('Origin', frontend);
      scanRequest.headers.contentType = ContentType.json;
      scanRequest.write(jsonEncode({'token': payload['token']}));
      final scanned = await scanRequest.close();
      expect(scanned.statusCode, 200);
      expect(scanned.headers.value('access-control-allow-origin'), frontend);
      final body = jsonDecode(await utf8.decoder.bind(scanned).join()) as Map;
      await host.login(body['ticket'] as String, 'an@example.com');
      await host.submit(body['ticket'] as String, '');
      expect(saves, 1);
    },
  );
  String scan() => host.scan(host.currentToken)['ticket'] as String;
  Future<String> login([String email = 'an@example.com']) async {
    final id = scan();
    await host.login(id, email);
    return id;
  }

  test(
    'QR rotates at 15 seconds; a valid scan has 3 minutes to finish',
    () async {
      await setupHost();
      final token = host.currentToken;
      final id = scan();
      now = now.add(const Duration(seconds: 14));
      expect(host.currentToken, token);
      now = now.add(const Duration(seconds: 1));
      expect(host.currentToken, isNot(token));
      expect(() => host.scan(token), throwsA(status(410)));
      await host.login(id, 'an@example.com');
      await host.submit(id, '');
      expect(
        book.attendanceFor(group).sessions.single.marks['SE000001'],
        AttendanceMark.present,
      );
      now = now.add(const Duration(seconds: 165));
      await expectLater(host.submit(id, ''), throwsA(status(410)));
    },
  );
  test('Google identity and exact class membership are required', () async {
    await setupHost();
    final id = scan();
    await expectLater(host.submit(id, ''), throwsA(status(401)));
    await expectLater(host.login(id, 'invalid'), throwsFormatException);
    await expectLater(
      host.login(id, 'outsider@example.com'),
      throwsA(status(403)),
    );
    expect(saves, 0);
    await host.login(id, 'an@example.com');
    await host.submit(id, '');
    expect(book.attendanceFor(group).history.last.action, 'qr_present');
  });
  test('resume retains the original deadline, identity and saved receipt only for its ticket', () async {
    await setupHost();
    final accepted = host.scan(host.currentToken);
    final ticket = accepted['ticket'] as String;
    now = now.add(const Duration(minutes: 2));
    final pending = host.resume(ticket);
    expect(pending['expiresAt'], accepted['expiresAt']);
    expect(pending.containsKey('identity'), false);
    expect(pending['nonce'], accepted['nonce']);
    await host.login(ticket, 'an@example.com');
    expect(
      host.resume(ticket)['identity'],
      containsPair('email', 'an@example.com'),
    );
    expect(host.progress['savedPresent'], 0);
    expect(host.progress['verifiedStudents'], 1);
    await host.submit(ticket, '');
    expect(host.resume(ticket)['submitted'], true);
    expect(host.progress['savedPresent'], 1);
    expect(() => host.resume('unknown'), throwsA(status(410)));
    now = DateTime.parse(accepted['expiresAt'] as String);
    expect(() => host.resume(ticket), throwsA(status(410)));
  });

  test('stopping revokes saved browser tickets without changing persisted attendance', () async {
    await setupHost();
    final ticket = await login();
    await host.submit(ticket, '');
    await host.stop();
    expect(() => host.resume(ticket), throwsA(status(410)));
    expect(
      book.attendanceFor(group).sessions.single.marks['SE000001'],
      AttendanceMark.present,
    );
  });
  test(
    'scan just before QR expiry keeps three minutes while late scans fail',
    () async {
      await setupHost();
      final started = now;
      final oldQr = host.currentToken;
      now = started.add(const Duration(seconds: 14, milliseconds: 999));
      final accepted = host.scan(oldQr);
      final ticket = accepted['ticket'] as String;
      final deadline = DateTime.parse(accepted['expiresAt'] as String);
      expect(deadline, now.add(const Duration(minutes: 3)));
      now = started.add(const Duration(seconds: 15));
      // No teacher refresh is needed for the old QR to become invalid.
      expect(() => host.scan(oldQr), throwsA(status(410)));
      for (var i = 0; i < 8; i++) {
        host.currentToken;
        now = now.add(const Duration(seconds: 15));
      }
      await host.login(ticket, 'an@example.com');
      now = deadline.subtract(const Duration(milliseconds: 1));
      expect((await host.submit(ticket, ''))['status'], 'P');
      expect(saves, 1);
    },
  );

  test('scan deadline is fixed from acceptance and expires exactly at three minutes', () async {
    await setupHost();
    final accepted = host.scan(host.currentToken);
    final ticket = accepted['ticket'] as String;
    final deadline = DateTime.parse(accepted['expiresAt'] as String);
    now = deadline.subtract(const Duration(seconds: 1));
    await host.login(ticket, 'an@example.com');
    now = deadline;
    await expectLater(host.submit(ticket, ''), throwsA(status(410)));
    await expectLater(
      host.login(ticket, 'an@example.com'),
      throwsA(status(410)),
    );
    expect(saves, 0);
    expect(book.attendanceFor(group).sessions.single.marks, isEmpty);
  });
  test(
    'secret never occurs in QR; wrong code can retry, bounded at 5 attempts',
    () async {
      await setupHost(secret: true);
      final id = await login();
      expect(host.secret, matches(r'^\d{6}$'));
      expect(host.qrUrl, isNot(contains(host.secret)));
      await expectLater(host.submit(id, 'wrong'), throwsA(status(400)));
      expect(saves, 0);
      await host.submit(id, host.secret);
      expect(saves, 1);
      final second = await login('binh@example.com');
      for (var i = 0; i < 5; i++) {
        await expectLater(host.submit(second, 'wrong'), throwsA(status(400)));
      }
      await expectLater(host.submit(second, host.secret), throwsA(status(429)));
    },
  );
  test('simultaneous students and duplicate submits do not lose marks or duplicate audit', () async {
    await setupHost();
    final a = await login();
    final b = await login('binh@example.com');
    save = (_) => Future.delayed(const Duration(milliseconds: 20));
    await Future.wait([
      host.submit(a, ''),
      host.submit(b, ''),
      host.submit(a, ''),
    ]);
    expect(saves, 2);
    expect(book.attendanceFor(group).sessions.single.marks.length, 2);
  });
  test('failed file save does not return success and can be retried', () async {
    await setupHost();
    final id = await login();
    save = (_) async => throw const FileSystemException('Disk full');
    await expectLater(host.submit(id, ''), throwsA(isA<FileSystemException>()));
    expect(book.attendanceFor(group).sessions.single.marks, isEmpty);
    save = null;
    await host.submit(id, '');
    expect(saves, 1);
  });
  test(
    'multiple scans of one identity share one saved mark and audit event',
    () async {
      await setupHost();
      final tickets = await Future.wait(List.generate(6, (_) => login()));
      save = (_) => Future.delayed(const Duration(milliseconds: 10));
      final results = await Future.wait(
        tickets.map((id) => host.submit(id, '')),
      );
      expect(results.where((result) => result['duplicate'] == false).length, 1);
      expect(results.where((result) => result['duplicate'] == true).length, 5);
      expect(saves, 1);
      expect(book.attendanceFor(group).sessions.single.marks.length, 1);
      expect(
        book
            .attendanceFor(group)
            .history
            .where((e) => e.action == 'qr_present')
            .length,
        1,
      );
      now = now.add(const Duration(seconds: 15));
      final nextQr = await login();
      expect((await host.submit(nextQr, ''))['duplicate'], true);
      expect(saves, 1);
    },
  );

  test(
    'a failed queued save permits another scan to save once without duplicates',
    () async {
      await setupHost();
      final first = await login();
      final second = await login();
      var attempts = 0;
      save = (_) async {
        if (++attempts == 1) throw const FileSystemException('Disk full');
      };
      final failed = expectLater(
        host.submit(first, ''),
        throwsA(isA<FileSystemException>()),
      );
      final saved = host.submit(second, '');
      await failed;
      expect((await saved)['duplicate'], false);
      expect((await host.submit(first, ''))['duplicate'], true);
      expect(saves, 1);
      expect(
        book
            .attendanceFor(group)
            .history
            .where((e) => e.action == 'qr_present')
            .length,
        1,
      );
    },
  );
  test(
    'close waits for an in-flight save and rejects subsequent submits',
    () async {
      await setupHost();
      final a = await login();
      final b = await login('binh@example.com');
      final entered = Completer<void>();
      final release = Completer<void>();
      save = (_) async {
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      final first = host.submit(a, '');
      await entered.future;
      final closing = host.finalize();
      final rejected = expectLater(host.submit(b, ''), throwsA(status(410)));
      release.complete();
      await first;
      await closing;
      await rejected;
      final result = book.attendanceFor(group).sessions.single;
      expect(result.state, SessionState.closed);
      expect(result.marks, {
        'SE000001': AttendanceMark.present,
        'SE000002': AttendanceMark.absent,
        'SE000003': AttendanceMark.absent,
      });
    },
  );
  test(
    'stop during Google verification cannot authenticate or mark after stop',
    () async {
      await setupHost();
      final id = scan();
      final entered = Completer<void>();
      final release = Completer<void>();
      verifier.gate = () async {
        entered.complete();
        await release.future;
      };
      final pending = expectLater(
        host.login(id, 'an@example.com'),
        throwsA(status(410)),
      );
      await entered.future;
      final stopping = host.stop();
      release.complete();
      await stopping;
      await pending;
      expect(saves, 0);
    },
  );
  test('teacher A is protected; stop does not mark others absent', () async {
    await setupHost();
    book = service.mark(
      book,
      group,
      session,
      'SE000001',
      AttendanceMark.absent,
      DateTime(2026, 9, 7, 8),
    );
    final id = await login();
    await expectLater(host.submit(id, ''), throwsA(status(409)));
    await host.stop();
    expect(book.attendanceFor(group).sessions.single.marks.length, 1);
    expect(book.attendanceFor(group).sessions.single.state, SessionState.open);
  });
  test('local HTTP serves page, enforces origin/content type, exposes no roster, persists P', () async {
    final directory = await Directory.systemTemp.createTemp('qr-host-');
    addTearDown(() => directory.delete(recursive: true));
    save = MarkbookStore(directory).save;
    await setupHost();
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    Future<(int, String)> request(
      String path, {
      Map<String, Object?>? json,
      String? origin,
    }) async {
      final r = await client.openUrl(
        json == null ? 'GET' : 'POST',
        Uri.parse('${host.localOrigin}$path'),
      );
      if (json != null) {
        r.headers.contentType = ContentType.json;
        r.headers.set('Origin', origin ?? host.localOrigin);
        r.write(jsonEncode(json));
      }
      final response = await r.close();
      return (response.statusCode, await utf8.decoder.bind(response).join());
    }

    expect((await request('/')).$1, 200);
    expect((await request('/FA26.json')).$1, 404);
    expect(
      (await request(
        '/api/scan',
        json: {'token': host.currentToken},
        origin: 'https://evil.example',
      )).$1,
      403,
    );
    final scanResponse = await request(
      '/api/scan',
      json: {'token': host.currentToken},
    );
    final id = (jsonDecode(scanResponse.$2) as Map)['ticket'];
    expect(scanResponse.$2, isNot(contains('an@example.com')));
    expect(
      (await request(
        '/api/login',
        json: {'ticket': id, 'credential': 'an@example.com'},
      )).$1,
      200,
    );
    expect(
      (await request('/api/submit', json: {'ticket': id, 'secret': ''})).$1,
      200,
    );
    expect(
      (await MarkbookStore(directory).load()).markbook!
          .attendanceFor(group)
          .sessions
          .single
          .marks['SE000001'],
      AttendanceMark.present,
    );
  });
}
