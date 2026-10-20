import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fap_helper_v1/data/markbook_store.dart';
import 'package:fap_helper_v1/data/markbook_workspace.dart';
import 'package:fap_helper_v1/domain/attendance_models.dart';
import 'package:fap_helper_v1/domain/attendance_service.dart';
import 'package:fap_helper_v1/domain/attendance_reset.dart';
import 'package:fap_helper_v1/domain/markbook.dart';

import 'support/attendance_fixture.dart';

class _FailingStore extends MarkbookStore {
  _FailingStore(super.directory);
  bool fail = false;
  @override
  Future<void> save(Markbook markbook) async {
    if (fail) throw const FileSystemException('Disk full');
    await super.save(markbook);
  }
}

void main() {
  const service = AttendanceService();
  const group = 'PRM393/SE1920';
  const session = '2026-09-07/1';
  final now = DateTime(2026, 9, 7, 8);
  late Directory directory;
  late _FailingStore store;
  late MarkbookWorkspace workspace;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fap-workspace-');
    store = _FailingStore(directory);
    workspace = MarkbookWorkspace(store);
    await workspace.replace(
      service.open(attendanceFixture(), group, session, now),
      expected: null,
    );
  });
  tearDown(() async {
    workspace.dispose();
    await directory.delete(recursive: true);
  });

  test('native and web changes serialize against fresh state and reject stale snapshots', () async {
    final stale = workspace.book!;
    await Future.wait([
      workspace.change(
        (book) => service.mark(
          book,
          group,
          session,
          'SE000001',
          AttendanceMark.present,
          now,
        ),
      ),
      workspace.change(
        (book) => service.mark(
          book,
          group,
          session,
          'SE000002',
          AttendanceMark.absent,
          now,
        ),
      ),
    ]);
    expect(workspace.requireBook.attendanceFor(group).sessions.single.marks, {
      'SE000001': AttendanceMark.present,
      'SE000002': AttendanceMark.absent,
    });
    await expectLater(
      workspace.replace(
        service.mark(
          stale,
          group,
          session,
          'SE000003',
          AttendanceMark.present,
          now,
        ),
        expected: stale,
      ),
      throwsA(isA<WorkspaceConflict>()),
    );
    expect(
      (await store.load()).markbook!.toJson(),
      workspace.requireBook.toJson(),
    );
  });

  test('a failed durable write neither publishes a revision nor poisons later saves', () async {
    final revision = workspace.revision;
    store.fail = true;
    await expectLater(
      workspace.change(
        (book) => service.mark(
          book,
          group,
          session,
          'SE000001',
          AttendanceMark.present,
          now,
        ),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(workspace.revision, revision);
    expect(
      workspace.requireBook.attendanceFor(group).sessions.single.marks,
      isEmpty,
    );
    store.fail = false;
    await workspace.change(
      (book) => service.mark(
        book,
        group,
        session,
        'SE000001',
        AttendanceMark.present,
        now,
      ),
      expectedRevision: revision,
    );
    await expectLater(
      workspace.change((book) => book, expectedRevision: revision),
      throwsA(isA<WorkspaceConflict>()),
    );
  });

  test('configured absence warning persists through marks, totals and reset; old JSON stays readable', () async {
    await workspace.change(
      (book) => service.setWarningThreshold(book, group, 25, now),
    );
    await workspace.change((book) => service.setTotal(book, group, 10, now));
    await workspace.change(
      (book) => service.mark(
        book,
        group,
        session,
        'SE000001',
        AttendanceMark.absent,
        now,
      ),
    );
    final saved = (await store.load()).markbook!;
    expect(saved.attendanceFor(group).absenceWarningPercent, 25);
    expect(
      resetAttendance(
        saved,
        groupId: group,
      ).attendanceFor(group).absenceWarningPercent,
      25,
    );
    final old = saved.toJson();
    ((old['attendance'] as Map)[group] as Map).remove('absenceWarningPercent');
    expect(
      Markbook.fromJson(old).attendanceFor(group).absenceWarningPercent,
      isNull,
    );
    expect(
      () => service.setWarningThreshold(saved, group, 101, now),
      throwsFormatException,
    );
  });
}
