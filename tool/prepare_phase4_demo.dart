import 'dart:convert';
import 'dart:io';

import 'package:fap_helper_v1/data/attendance_csv.dart';
import 'package:fap_helper_v1/domain/attendance_models.dart';
import 'package:fap_helper_v1/domain/attendance_service.dart';

import '../test/support/attendance_fixture.dart';

void main() {
  const service = AttendanceService();
  var book = attendanceFixture();
  final group = book.groups.first.id;
  final now = DateTime(2026, 9, 16, 10);
  book = service.open(book, group, '2026-09-07/1', now);
  book = service.mark(
    book,
    group,
    '2026-09-07/1',
    'SE000001',
    AttendanceMark.present,
    now,
  );
  book = service.mark(
    book,
    group,
    '2026-09-07/1',
    'SE000003',
    AttendanceMark.present,
    now,
  );
  book = service.close(book, group, '2026-09-07/1', now);
  book = service.open(book, group, '2026-09-10/1', now);
  book = service.close(book, group, '2026-09-10/1', now);
  final dir = Directory('mock-fap/demo')..createSync(recursive: true);
  File('${dir.path}/FA26-demo.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(book.toJson()),
  );
  File('${dir.path}/FA26-demo.csv').writeAsStringSync(
    AttendanceCsv().generate(book, group, DateTime.utc(2026, 9, 16)),
  );
  stdout.writeln('Generated synthetic demo: 3 students, 2 closed sessions.');
}
