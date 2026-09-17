import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fap_helper_v1/data/markbook_store.dart';
import 'package:fap_helper_v1/domain/attendance_models.dart';
import 'package:fap_helper_v1/domain/attendance_service.dart';
import 'package:fap_helper_v1/domain/markbook.dart';

import 'support/attendance_fixture.dart';

void main() {
  const service = AttendanceService();
  const group = 'PRM393/SE1920';
  const first = '2026-09-07/1';
  final now = DateTime(2026, 9, 15, 10);
  Markbook opened() => service.open(attendanceFixture(), group, first, now);
  Markbook closed() => service.close(
    service.mark(
      opened(),
      group,
      first,
      'SE000001',
      AttendanceMark.present,
      now,
    ),
    group,
    first,
    now,
  );

  test('planned sessions stay blank, sequence uses actual dates and starts on term start', () {
    final book = attendanceFixture();
    final sessions = service.schedule(
      book.groups.single,
      book.attendanceFor(group),
      DateTime(2026, 9, 28),
    );
    expect(sessions.map((s) => s.session.date.day), [
      7,
      10,
      14,
      17,
      21,
      24,
      28,
    ]);
    expect(sessions.map((s) => s.number), [1, 2, 3, 4, 5, 6, 7]);
    expect(sessions.every((s) => s.session.marks.isEmpty), true);
    expect(
      service.summary(book.attendanceFor(group), 'SE000001').absencePercent,
      isNull,
    );
  });

  test('requires open session, blocks future and foreign students, allows only one open per class', () {
    expect(
      () => service.mark(
        attendanceFixture(),
        group,
        first,
        'SE000001',
        AttendanceMark.present,
        now,
      ),
      throwsFormatException,
    );
    expect(
      () => service.open(attendanceFixture(), group, '2026-09-17/1', now),
      throwsFormatException,
    );
    expect(
      () => service.mark(
        opened(),
        group,
        first,
        'SE999999',
        AttendanceMark.present,
        now,
      ),
      throwsFormatException,
    );
    expect(
      () => service.open(opened(), group, '2026-09-10/1', now),
      throwsFormatException,
    );
  });

  test('marking is immutable, repeat is idempotent, clearing only possible before close', () {
    final initial = opened();
    final marked = service.mark(
      initial,
      group,
      first,
      'SE000001',
      AttendanceMark.present,
      now,
    );
    expect(initial.attendanceFor(group).sessions.single.marks, isEmpty);
    expect(
      service.mark(
        marked,
        group,
        first,
        'SE000001',
        AttendanceMark.present,
        now,
      ),
      same(marked),
    );
    final cleared = service.mark(marked, group, first, 'SE000001', null, now);
    expect(cleared.attendanceFor(group).sessions.single.marks, isEmpty);
    expect(cleared.attendanceFor(group).history.last.before, 'P');
  });

  test(
    'close fills every remaining student A and preserves explicit marks',
    () {
      final result = closed();
      final session = result.attendanceFor(group).sessions.single;
      expect(session.state, SessionState.closed);
      expect(session.marks['SE000001'], AttendanceMark.present);
      expect(session.marks['SE000002'], AttendanceMark.absent);
      expect(session.marks['SE000003'], AttendanceMark.absent);
      expect(
        result
            .attendanceFor(group)
            .history
            .where((e) => e.action == 'close_absent')
            .length,
        2,
      );
      expect(
        () => service.close(result, group, first, now),
        throwsFormatException,
      );
      expect(
        () => service.open(result, group, first, now),
        throwsFormatException,
      );
    },
  );

  test('correction requires reason and preserves close time with before/after audit', () {
    final original = closed();
    expect(
      () => service.mark(
        original,
        group,
        first,
        'SE000002',
        AttendanceMark.present,
        now,
      ),
      throwsFormatException,
    );
    expect(
      () => service.mark(
        original,
        group,
        first,
        'SE000002',
        null,
        now,
        reason: 'test',
      ),
      throwsFormatException,
    );
    final corrected = service.mark(
      original,
      group,
      first,
      'SE000002',
      AttendanceMark.present,
      now,
      reason: 'Mất mạng khi điểm danh',
    );
    final event = corrected.attendanceFor(group).history.last;
    expect(event.action, 'correct');
    expect(event.before, 'A');
    expect(event.after, 'P');
    expect(event.at, DateTime.utc(2026, 9, 15, 3));
    expect(event.reason, 'Mất mạng khi điểm danh');
    expect(
      corrected.attendanceFor(group).sessions.single.closedAt,
      original.attendanceFor(group).sessions.single.closedAt,
    );
  });

  test(
    'percent uses all required lessons, not just lessons already closed',
    () {
      final book = service.setTotal(closed(), group, 10, now);
      final summary = service.summary(book.attendanceFor(group), 'SE000002');
      expect(summary.absent, 1);
      expect(summary.present, 0);
      expect(summary.absencePercent, 10);
      expect(
        service.summary(book.attendanceFor(group), 'SE000001').absencePercent,
        0,
      );
      expect(
        service
            .summary(
              service.setTotal(book, group, null, now).attendanceFor(group),
              'SE000002',
            )
            .absencePercent,
        isNull,
      );
    },
  );

  test('cancel and makeup change denominator without moving saved marks to another date', () {
    var book = service.setTotal(closed(), group, 10, now);
    book = service.cancel(
      book,
      group,
      '2026-09-10/1',
      now,
      'Nghỉ theo thông báo',
    );
    expect(service.requiredTotal(book.attendanceFor(group)), 9);
    expect(
      service.onDate(
        book.groups.single,
        book.attendanceFor(group),
        DateTime(2026, 9, 10),
      ),
      isEmpty,
    );
    book = service.addMakeup(
      book,
      group,
      DateTime(2026, 9, 11),
      2,
      now,
      'Học bù buổi nghỉ',
    );
    expect(service.requiredTotal(book.attendanceFor(group)), 10);
    expect(
      book
          .attendanceFor(group)
          .sessions
          .firstWhere((s) => s.id == first)
          .marks['SE000001'],
      AttendanceMark.present,
    );
    final row = service
        .onDate(
          book.groups.single,
          book.attendanceFor(group),
          DateTime(2026, 9, 11),
        )
        .single;
    expect(row.session.slot, 2);
    expect(row.number, 2);
    expect(
      () => service.cancel(book, group, first, now, 'Không hợp lệ'),
      throwsFormatException,
    );
    book = service.restore(book, group, '2026-09-10/1', now);
    expect(service.requiredTotal(book.attendanceFor(group)), 11);
  });

  test('cancel future date beyond default window; makeup extends schedule through stored date', () {
    var book = service.cancel(
      attendanceFixture(),
      group,
      '2026-11-02/1',
      now,
      'Nghỉ lễ',
    );
    book = service.addMakeup(
      book,
      group,
      DateTime(2026, 11, 3),
      2,
      now,
      'Học bù',
    );
    final plan = service.schedule(
      book.groups.single,
      book.attendanceFor(group),
      now,
    );
    expect(plan.last.session.id, '2026-11-03/2');
    expect(plan.last.number, 17);
  });

  test('total cannot hide stored lessons or overlap an existing makeup', () {
    var book = service.open(attendanceFixture(), group, '2026-09-14/1', now);
    expect(() => service.setTotal(book, group, 2, now), throwsFormatException);
    expect(() => service.setTotal(book, group, 0, now), throwsFormatException);
    book = service.setTotal(attendanceFixture(), group, 1, now);
    book = service.addMakeup(
      book,
      group,
      DateTime(2026, 9, 10),
      1,
      now,
      'Học bổ sung',
    );
    expect(() => service.setTotal(book, group, 2, now), throwsFormatException);
    expect(
      () => service.setTotal(book, group, null, now),
      throwsFormatException,
    );
  });

  test(
    'makeup rejects a duplicate slot or collision with another teaching class',
    () {
      final base = attendanceFixture();
      final another = CourseGroup(
        sheetName: '22_PRN232_SE1920',
        subjectCode: 'PRN232',
        classCode: 'SE1920',
        dayPair: 2,
        slotNumber: 2,
        students: base.groups.single.students,
      );
      final book = Markbook(
        sourceName: base.sourceName,
        importedAt: base.importedAt,
        groups: [...base.groups, another],
      );
      expect(
        () => service.addMakeup(
          book,
          group,
          DateTime(2026, 9, 7),
          1,
          now,
          'Học bù',
        ),
        throwsFormatException,
      );
      expect(
        () => service.addMakeup(
          book,
          group,
          DateTime(2026, 9, 8),
          2,
          now,
          'Học bù',
        ),
        throwsFormatException,
      );
      expect(
        () => service.addMakeup(
          book,
          group,
          DateTime(2026, 9, 1),
          1,
          now,
          'Học bù',
        ),
        throwsFormatException,
      );
    },
  );

  test('schema 1 migrates without dropping roster, schema 2 preserves full attendance on disk', () async {
    final temp = await Directory.systemTemp.createTemp('fap_phase2_migration_');
    addTearDown(() => temp.delete(recursive: true));
    final store = MarkbookStore(temp);
    final old = attendanceFixture().toJson()
      ..['schemaVersion'] = 1
      ..remove('attendance');
    await store.file.writeAsString(jsonEncode(old));
    final loaded = (await store.load()).markbook!;
    expect(loaded.groups.single.students.length, 3);
    expect(loaded.attendance, isEmpty);
    var updated = service.open(loaded, group, first, now);
    updated = service.close(updated, group, first, now);
    await store.save(updated);
    final restarted = (await MarkbookStore(temp).load()).markbook!;
    expect(restarted.toJson(), updated.toJson());
    expect(jsonDecode(await store.backup.readAsString())['schemaVersion'], 1);
  });

  test('schema 2 rejects missing students in a closed session and invalid slot states', () {
    final broken =
        jsonDecode(jsonEncode(closed().toJson())) as Map<String, dynamic>;
    (broken['attendance'][group]['sessions'][0]['marks'] as Map).remove(
      'SE000003',
    );
    expect(() => Markbook.fromJson(broken), throwsFormatException);
    final badSlot =
        jsonDecode(jsonEncode(closed().toJson())) as Map<String, dynamic>;
    badSlot['attendance'][group]['sessions'][0]['slot'] = 4;
    expect(() => Markbook.fromJson(badSlot), throwsFormatException);
  });

  test('re-import keeps marks/history and rejects deletion, roster or timetable changes', () {
    final original = closed();
    final refreshed = original.mergeImport(
      attendanceFixture(name: 'Nguyễn Văn An đã sửa'),
    );
    expect(
      refreshed.attendanceFor(group).toJson(),
      original.attendanceFor(group).toJson(),
    );
    expect(
      refreshed.groups.single.students.first.fullName,
      'Nguyễn Văn An đã sửa',
    );
    final base = attendanceFixture();
    final g = base.groups.single;
    Markbook withGroups(List<CourseGroup> groups) => Markbook(
      sourceName: 'FA26_updated.xlsx',
      importedAt: now,
      groups: groups,
    );
    expect(() => original.mergeImport(withGroups([])), throwsFormatException);
    expect(
      () => original.mergeImport(
        withGroups([
          CourseGroup(
            sheetName: g.sheetName,
            subjectCode: g.subjectCode,
            classCode: g.classCode,
            dayPair: 2,
            slotNumber: g.slotNumber,
            students: g.students,
          ),
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => original.mergeImport(
        withGroups([
          CourseGroup(
            sheetName: g.sheetName,
            subjectCode: g.subjectCode,
            classCode: g.classCode,
            dayPair: g.dayPair,
            slotNumber: g.slotNumber,
            students: g.students.take(2).toList(),
          ),
        ]),
      ),
      throwsFormatException,
    );
  });
}
