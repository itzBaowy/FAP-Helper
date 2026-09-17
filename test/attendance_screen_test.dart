import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_helper_v1/data/attendance_csv.dart';
import 'package:fap_helper_v1/domain/attendance_models.dart';
import 'package:fap_helper_v1/domain/attendance_service.dart';
import 'package:fap_helper_v1/domain/markbook.dart';
import 'package:fap_helper_v1/ui/attendance_screen.dart';

import 'support/attendance_fixture.dart';

class CapturingCsv extends AttendanceCsv {
  String? content;
  @override
  Future<void> save(String path, String content) async {
    this.content = content;
  }
}

void main() {
  const group = 'PRM393/SE1920';
  const first = '2026-09-07/1';
  final now = DateTime(2026, 9, 7, 8);
  const service = AttendanceService();

  Future<void> mount(
    WidgetTester tester,
    Markbook book,
    Future<void> Function(Markbook) save, {
    AttendanceCsv? exporter,
    double width = 1440,
    double height = 940,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AttendanceScreen(
          book: book,
          groupId: group,
          now: () => now,
          onSave: save,
          exporter: exporter,
          pickCsv: (_) async => 'attendance.csv',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> mark(WidgetTester tester, String roll, String label) async {
    final target = find.byKey(ValueKey('mark-$roll-$first'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('small desktop window remains usable without layout overflow', (
    tester,
  ) async {
    await mount(
      tester,
      attendanceFixture(),
      (_) async {},
      width: 800,
      height: 600,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'manual P, filtered close, correction with reason and CSV export',
    (tester) async {
      var saved = attendanceFixture();
      final exporter = CapturingCsv();
      await mount(tester, saved, (book) async {
        saved = book;
      }, exporter: exporter);
      expect(find.text('Mở buổi'), findsOneWidget);
      await tester.tap(find.text('Mở buổi'));
      await tester.pumpAndSettle();
      await mark(tester, 'SE000001', 'P · Có mặt');
      await tester.enterText(find.byType(TextField), 'SE000001');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chốt danh sách'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 sinh viên chưa ghi nhận'), findsOneWidget);
      await tester.tap(find.text('Xác nhận chốt'));
      await tester.pumpAndSettle();
      expect(
        saved
            .attendanceFor(group)
            .sessions
            .single
            .marks
            .values
            .where((m) => m == AttendanceMark.absent)
            .length,
        2,
      );
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await mark(tester, 'SE000002', 'P · Có mặt');
      expect(find.text('Sửa điểm danh sau khi chốt'), findsOneWidget);
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(find.text('Nhập lý do ít nhất 3 ký tự.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('attendance-input')),
        'Mất mạng trong lớp',
      );
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(saved.attendanceFor(group).history.last.action, 'correct');
      expect(
        saved.attendanceFor(group).sessions.single.marks['SE000002'],
        AttendanceMark.present,
      );
      await tester.tap(find.byTooltip('Xuất CSV'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xuất buổi đang chọn'));
      await tester.pumpAndSettle();
      expect(exporter.content, contains('"Trần Bình","binh","P"'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed disk save leaves displayed marks and current book unchanged',
    (tester) async {
      var attempts = 0;
      final book = service.open(attendanceFixture(), group, first, now);
      await mount(tester, book, (_) async {
        attempts++;
        throw const FileSystemException('Disk full');
      });
      await mark(tester, 'SE000001', 'P · Có mặt');
      expect(find.text('Chưa thể thực hiện'), findsOneWidget);
      expect(attempts, 1);
      await tester.tap(find.widgetWithText(TextButton, 'Đóng'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Buổi đang chọn: 0 P · 0 A · 3 chưa ghi nhận'),
        findsOneWidget,
      );
      expect(book.attendanceFor(group).sessions.single.marks, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'controls disable during save so rapid actions cannot overwrite one another',
    (tester) async {
      final pending = Completer<void>();
      await mount(tester, attendanceFixture(), (_) => pending.future);
      await tester.tap(find.text('Mở buổi'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('open-session')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == 'Đóng',
              ),
            )
            .onPressed,
        isNull,
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Chốt danh sách'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('class total is configurable and future sessions remain blank', (
    tester,
  ) async {
    var saved = attendanceFixture();
    await mount(tester, saved, (book) async {
      saved = book;
    }, width: 800);
    await tester.tap(find.text('Tổng số buổi'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('attendance-input')),
      '10',
    );
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(saved.attendanceFor(group).plannedTotal, 10);
    expect(saved.attendanceFor(group).sessions, isEmpty);
    expect(find.text('Tổng phải học: 10'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
