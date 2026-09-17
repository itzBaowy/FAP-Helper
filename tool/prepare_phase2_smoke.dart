// Creates a separate synthetic profile for native Windows acceptance testing.
// Never writes to %APPDATA% or copies any real student roster.
import 'dart:io';

import 'package:fap_helper_v1/data/markbook_store.dart';
import 'package:fap_helper_v1/domain/attendance_service.dart';

import '../test/support/attendance_fixture.dart';

Future<void> main() async {
  final path = Directory('build/phase2-smoke-profile');
  if (await File('${path.path}/FA26.json').exists()) {
    stderr.writeln(
      'Smoke profile already exists; choose a fresh build directory for a new run.',
    );
    exitCode = 1;
    return;
  }
  final book = const AttendanceService().setTotal(
    attendanceFixture(),
    'PRM393/SE1920',
    10,
    DateTime(2026, 9, 15, 10),
  );
  await MarkbookStore(path).save(book);
  stdout.writeln('Synthetic profile ready: ${path.absolute.path}');
}
