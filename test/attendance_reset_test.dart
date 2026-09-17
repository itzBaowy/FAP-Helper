import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_helper_v1/data/markbook_store.dart';
import 'package:fap_helper_v1/domain/attendance_models.dart';
import 'package:fap_helper_v1/domain/attendance_reset.dart';
import 'package:fap_helper_v1/domain/markbook.dart';
import 'package:fap_helper_v1/ui/reset_attendance_dialog.dart';

import 'support/workbook_fixture.dart';

Markbook markedBook() {
  var book = sampleBook();
  for (final g in book.groups.take(2)) {
    book = book.withAttendance(
      g.id,
      CourseAttendance(
        plannedTotal: 20,
        sessions: [
          AttendanceSession(
            date: DateTime(2026, 9, 7),
            slot: g.slotNumber,
            state: SessionState.closed,
            openedAt: DateTime.utc(2026, 9, 7),
            closedAt: DateTime.utc(2026, 9, 7, 5),
            marks: {g.students.first.rollNumber: AttendanceMark.present},
          ),
          AttendanceSession(
            date: DateTime(2026, 9, 10),
            slot: g.slotNumber,
            state: SessionState.cancelled,
            note: 'Holiday',
          ),
          AttendanceSession(
            date: DateTime(2026, 9, 13),
            slot: g.slotNumber,
            isMakeup: true,
            note: 'Makeup',
          ),
        ],
      ),
    );
  }
  return book;
}

void main() {
  test('class reset preserves other classes, calendar and audit; all reset clears attendance', () {
    final book = markedBook();
    final reset = resetAttendance(book, groupId: book.groups.first.id);
    final data = reset.attendanceFor(book.groups.first.id);
    expect(data.plannedTotal, 20);
    expect(data.sessions.first.state, SessionState.planned);
    expect(data.sessions.first.openedAt, isNull);
    expect(data.sessions.first.closedAt, isNull);
    expect(data.sessions.first.marks, isEmpty);
    expect(data.sessions[1].state, SessionState.cancelled);
    expect(data.sessions[1].note, 'Holiday');
    expect(data.sessions[2].isMakeup, true);
    expect(data.history.last.action, 'reset');
    expect(
      reset.attendanceFor(book.groups[1].id).toJson(),
      book.attendanceFor(book.groups[1].id).toJson(),
    );
    expect(reset.groups, book.groups);
    final all = resetAttendance(reset);
    expect(all.attendance.values.any(hasAttendanceToReset), false);
    expect(Markbook.fromJson(all.toJson()).groups.length, 3);
    expect(identical(resetAttendance(all), all), true);
    expect(
      () => resetAttendance(book, groupId: 'missing'),
      throwsFormatException,
    );
  });

  test(
    'snapshot survives subsequent saves and blocked backup prevents reset',
    () async {
      final dir = await Directory.systemTemp.createTemp('fap_reset_test_');
      addTearDown(() => dir.delete(recursive: true));
      final store = MarkbookStore(dir);
      final book = markedBook();
      await store.save(book);
      final result = await store.reset(book);
      expect(
        jsonDecode(await File(result.backupPath!).readAsString()),
        book.toJson(),
      );
      await store.save(result.book);
      expect(
        jsonDecode(await File(result.backupPath!).readAsString()),
        book.toJson(),
      );
      expect(
        (await store.load()).markbook!.attendance.values.any(
          hasAttendanceToReset,
        ),
        false,
      );
      final blockedDir = Directory('${dir.path}/blocked');
      await blockedDir.create();
      final blocked = MarkbookStore(blockedDir);
      await blocked.save(book);
      final before = await blocked.file.readAsString();
      await File('${blockedDir.path}/backups').writeAsString('block');
      await expectLater(
        blocked.reset(book),
        throwsA(isA<FileSystemException>()),
      );
      expect(await blocked.file.readAsString(), before);
    },
  );

  testWidgets(
    'confirmation required; cancel does not select a reset; all scope selectable',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    builder: (_) => ResetAttendanceDialog(book: markedBook()),
                  );
                },
                child: const Text('Launch'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Xác nhận reset'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Toàn bộ kỳ FA26').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'RESET');
      await tester.pump();
      await tester.tap(find.text('Xác nhận reset'));
      await tester.pumpAndSettle();
      expect(result, '*');
    },
  );
}
