import 'package:flutter_test/flutter_test.dart';
import 'package:fap_helper_v1/domain/attendance_models.dart';
import 'package:fap_helper_v1/domain/attendance_reset.dart';
import 'package:fap_helper_v1/domain/attendance_service.dart';
import 'package:fap_helper_v1/domain/markbook.dart';
import 'package:fap_helper_v1/domain/session_attendance_report.dart';

import 'support/attendance_fixture.dart';

void main() {
  const service = AttendanceService();
  const group = 'PRM393/SE1920';
  const session = '2026-09-07/1';
  final now = DateTime(2026, 9, 7, 8);
  Markbook opened() => service.open(attendanceFixture(), group, session, now);
  SessionAttendanceReport report(Markbook book) => SessionAttendanceReport(
    group: book.groups.single,
    data: book.attendanceFor(group),
    session: book
        .attendanceFor(group)
        .sessions
        .firstWhere((s) => s.id == session),
  );

  test(
    'uses saved marks, combines status with search, and sorts latest changes',
    () {
      var book = service.mark(
        opened(),
        group,
        session,
        'SE000001',
        AttendanceMark.present,
        now,
        fromQr: true,
      );
      book = service.mark(
        book,
        group,
        session,
        'SE000002',
        AttendanceMark.present,
        now.add(const Duration(seconds: 8)),
      );
      final result = report(book);
      expect(result.count(AttendanceFilter.all), 3);
      expect(result.count(AttendanceFilter.present), 2);
      expect(result.count(AttendanceFilter.unmarked), 1);
      expect(
        result.select(newestFirst: true).map((e) => e.student.rollNumber),
        ['SE000002', 'SE000001', 'SE000003'],
      );
      expect(
        result
            .select(filter: AttendanceFilter.present, query: 'SE000001 an@')
            .single
            .source,
        'QR · Google',
      );
      expect(
        result.select(filter: AttendanceFilter.unmarked, query: 'SE000001'),
        isEmpty,
      );
      expect(result.entries.first.event!.at, DateTime.utc(2026, 9, 7, 1));
      expect(result.select().first.student.rollNumber, 'SE000001');
    },
  );

  test('cleared marks, corrections, other sessions and resets retain accurate metadata', () {
    var book = service.mark(
      opened(),
      group,
      session,
      'SE000001',
      AttendanceMark.present,
      now,
      fromQr: true,
    );
    book = service.mark(book, group, session, 'SE000001', null, now);
    expect(report(book).entries.first.event, isNull);
    book = service.close(book, group, session, now);
    expect(report(book).entries.first.source, 'Chốt buổi');
    book = service.mark(
      book,
      group,
      session,
      'SE000001',
      AttendanceMark.present,
      now,
      reason: 'Sửa theo xác nhận',
    );
    expect(report(book).entries.first.source, 'Sửa sau chốt');
    book = service.open(book, group, '2026-09-10/1', DateTime(2026, 9, 10, 8));
    book = service.mark(
      book,
      group,
      '2026-09-10/1',
      'SE000001',
      AttendanceMark.absent,
      DateTime(2026, 9, 10, 8),
    );
    expect(report(book).entries.first.source, 'Sửa sau chốt');
    book = service.open(
      resetAttendance(book, groupId: group),
      group,
      session,
      now,
    );
    expect(
      report(book).entries.every((e) => e.event == null && e.mark == null),
      true,
    );
    // Imported saved marks can have no audit entry: do not reuse pre-reset times.
    final data = book.attendanceFor(group);
    final legacy = SessionAttendanceReport(
      group: book.groups.single,
      data: data,
      session: data.sessions
          .firstWhere((s) => s.id == session)
          .copyWith(marks: {'SE000001': AttendanceMark.present}),
    );
    expect(legacy.entries.first.source, 'Không có lịch sử');
  });
}
