import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fap_helper_v1/data/attendance_csv.dart';
import 'package:fap_helper_v1/domain/attendance_models.dart';
import 'package:fap_helper_v1/domain/attendance_service.dart';

import 'support/attendance_fixture.dart';

void main() {
  const group = 'PRM393/SE1920';
  const first = '2026-09-07/1';
  const service = AttendanceService();
  final now = DateTime(2026, 9, 15, 10);
  final exporter = AttendanceCsv();

  test('closed session exports one row per student with BOM, CRLF and stable identity', () {
    var book = service.open(attendanceFixture(), group, first, now);
    book = service.mark(
      book,
      group,
      first,
      'SE000001',
      AttendanceMark.present,
      now,
    );
    book = service.close(book, group, first, now);
    final csv = exporter.generate(
      book,
      group,
      DateTime.utc(2026, 9, 15),
      sessionId: first,
    );
    expect(csv.startsWith('\ufeff"SchemaVersion"'), true);
    expect(csv.split('\r\n').length, 5);
    expect(
      csv,
      contains(
        '"FA26/PRM393/SE1920/2026-09-07/1","1","2026-09-07","1","07:30","09:15"',
      ),
    );
    expect(csv, contains('"Nguyễn Văn An","an","P"'));
    expect(csv, contains('"Trần Bình","binh","A"'));
  });

  test(
    'export refuses unclosed selection; all-closed export excludes other slots',
    () {
      var book = service.open(attendanceFixture(), group, first, now);
      expect(
        () => exporter.generate(book, group, now, sessionId: first),
        throwsFormatException,
      );
      book = service.close(book, group, first, now);
      book = service.open(book, group, '2026-09-10/1', now);
      final csv = exporter.generate(book, group, now);
      expect(csv.split('\r\n').length, 5);
      expect(csv, isNot(contains('2026-09-10/1')));
    },
  );

  test('escapes quotes/newlines and neutralizes spreadsheet formulas', () {
    var book = service.open(
      attendanceFixture(name: '=SUM(1,2) "An"\nDòng hai'),
      group,
      first,
      now,
    );
    book = service.close(book, group, first, now);
    final csv = exporter.generate(book, group, now);
    expect(csv, contains('"\'=SUM(1,2) ""An""\nDòng hai"'));
  });

  test(
    'CSV reflects latest corrected mark and can be saved atomically',
    () async {
      final temp = await Directory.systemTemp.createTemp('fap_phase2_csv_');
      addTearDown(() => temp.delete(recursive: true));
      var book = service.close(
        service.open(attendanceFixture(), group, first, now),
        group,
        first,
        now,
      );
      book = service.mark(
        book,
        group,
        first,
        'SE000001',
        AttendanceMark.present,
        now,
        reason: 'Bổ sung có mặt',
      );
      final csv = exporter.generate(book, group, now);
      final path = '${temp.path}/điểm danh.csv';
      await exporter.save(path, csv);
      expect(await File(path).readAsString(), csv.substring(1));
      expect((await File(path).readAsBytes()).take(3).toList(), [
        239,
        187,
        191,
      ]);
      expect(temp.listSync().length, 1);
      await expectLater(
        exporter.save('${temp.path}/bad.txt', csv),
        throwsFormatException,
      );
    },
  );
}
