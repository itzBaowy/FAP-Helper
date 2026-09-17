import 'dart:convert';
import 'dart:io';

import 'package:fap_helper_v1/data/markbook_store.dart';
import 'package:fap_helper_v1/domain/attendance_service.dart';

import '../test/support/attendance_fixture.dart';

Future<void> main() async {
  final directory = Directory('build/phase3-smoke-profile');
  if (await directory.exists()) {
    throw StateError('Smoke profile already exists. Refusing to overwrite.');
  }
  final book = const AttendanceService().open(
    attendanceFixture(),
    'PRM393/SE1920',
    '2026-09-07/1',
    DateTime(2026, 9, 7, 8),
  );
  await MarkbookStore(directory).save(book);
  await File('${directory.path}/qr-settings.json').writeAsString(
    jsonEncode({
      'clientId': 'test.apps.googleusercontent.com',
      'domains': ['gmail.com', 'fpt.edu.vn'],
      'publicOrigin': '',
    }),
    flush: true,
  );
  stdout.writeln(
    'Created synthetic Phase 3 profile; the placeholder Client ID cannot sign in to real Google.',
  );
}
