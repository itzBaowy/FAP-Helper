// Test harness only. Never referenced by lib/main.dart or included in the release.
import 'dart:convert';
import 'dart:io';

import 'package:fap_helper_v1/data/google_identity.dart';
import 'package:fap_helper_v1/data/qr_attendance_host.dart';
import 'package:fap_helper_v1/domain/attendance_service.dart';

import '../test/support/attendance_fixture.dart';

class BrowserTestIdentity implements IdentityVerifier {
  @override
  Future<GoogleIdentity> verify(String credential, String nonce) async {
    if (credential != 'test-google-response') {
      throw const FormatException('Invalid test credential');
    }
    return const GoogleIdentity('an@example.com', 'browser-test-user');
  }

  @override
  void dispose() {}
}

Future<void> main(List<String> args) async {
  var book = const AttendanceService().open(
    attendanceFixture(),
    'PRM393/SE1920',
    '2026-09-07/1',
    DateTime(2026, 9, 7, 8),
  );
  final host = QrAttendanceHost(
    groupId: 'PRM393/SE1920',
    sessionId: '2026-09-07/1',
    clientId: 'test.apps.googleusercontent.com',
    requireSecret: true,
    verifier: BrowserTestIdentity(),
    readBook: () => book,
    saveBook: (next) async {
      book = next;
    },
    assets: {
      '/': await File('assets/student/index.html').readAsString(),
      '/app.js': await File('assets/student/app.js').readAsString(),
      '/style.css': await File('assets/student/style.css').readAsString(),
    },
  );
  await host.start();
  final vercel = args.contains('--vercel');
  host.activate(
    vercel ? 'https://student-test.vercel.app' : host.localOrigin,
    apiOrigin: vercel ? 'https://teacher-test.trycloudflare.com' : null,
  );
  stdout.writeln(
    jsonEncode({
      'url': host.qrUrl,
      'secret': host.secret,
      'localOrigin': host.localOrigin,
    }),
  );
  await for (final command
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (command == 'state') {
      stdout.writeln(jsonEncode(book.attendanceFor('PRM393/SE1920').toJson()));
    } else if (command == 'stop') {
      break;
    }
  }
  await host.stop();
}
