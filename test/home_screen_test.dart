import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_helper_v1/data/excel_importer.dart';
import 'package:fap_helper_v1/data/markbook_store.dart';
import 'package:fap_helper_v1/domain/markbook.dart';
import 'package:fap_helper_v1/main.dart';
import 'package:fap_helper_v1/ui/import_dialog.dart';

import 'support/workbook_fixture.dart';

class MemoryStore extends MarkbookStore {
  MemoryStore(this.book) : super(Directory('test-data'));
  Markbook? book;
  @override
  Future<LoadResult> load() async => LoadResult(book);
  @override
  Future<void> save(Markbook markbook) async {
    book = markbook;
  }
}

Future<void> desktop(WidgetTester tester, {double width = 1360}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('settings sidebar is accessible before importing classes', (
    tester,
  ) async {
    await desktop(tester);
    await tester.pumpWidget(MainApp(store: MemoryStore(null)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cấu hình'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cấu hình điểm danh'), findsOneWidget);
    expect(
      find.text('Google OAuth Client ID · Web application'),
      findsOneWidget,
    );
    expect(find.text('Import Excel'), findsNothing);
    expect(find.text('QR + mã bí mật'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'file selection, preview, cancel and save use the real import path',
    (tester) async {
      await desktop(tester);
      final directory = Directory.systemTemp.createTempSync(
        'fap_helper_ui_test_',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/FA26.xlsx')
        ..writeAsBytesSync(workbookFixture());
      final store = MemoryStore(null);
      await tester.pumpWidget(
        MainApp(
          store: store,
          pickFile: () async => file.path,
          now: () => DateTime(2026, 9, 7, 8),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> openPreview() async {
        await tester.tap(find.text('Import Excel').first);
        for (
          var attempt = 0;
          attempt < 100 && find.byType(ImportDialog).evaluate().isEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(find.byType(ImportDialog), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 300));
      }

      await openPreview();
      expect(store.book, isNull);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(store.book, isNull);
      await openPreview();
      await tester.tap(find.text('Xác nhận import'));
      await tester.pumpAndSettle();
      expect(store.book!.groups.single.subjectCode, 'PRN232');
      expect(find.text('Lịch dạy hôm nay'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('empty first launch exposes import without fake class data', (
    tester,
  ) async {
    await desktop(tester);
    await tester.pumpWidget(
      MainApp(store: MemoryStore(null), now: () => DateTime(2026, 9, 7, 8)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bắt đầu với danh sách lớp của bạn'), findsOneWidget);
    expect(find.text('Import Excel'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [1360.0, 800.0]) {
    testWidgets(
      'dashboard, filter, roster and timetable work at width $width',
      (tester) async {
        await desktop(tester, width: width);
        await tester.pumpWidget(
          MainApp(
            store: MemoryStore(sampleBook()),
            now: () => DateTime(2026, 9, 7, 8),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Lịch dạy hôm nay'), findsOneWidget);
        expect(find.text('Đang trong giờ'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Lớp học phần').first);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'SWD392'));
        await tester.pumpAndSettle();
        expect(find.text('SE1927'), findsOneWidget);
        expect(find.text('SE1917'), findsNothing);
        await tester.tap(find.text('SE1927'));
        await tester.pumpAndSettle();
        expect(find.text('Trần Bình'), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, 'no-match');
        await tester.pumpAndSettle();
        expect(find.text('Không tìm thấy sinh viên'), findsOneWidget);
        await tester.tap(find.byTooltip('Đóng'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Lịch tuần').first);
        await tester.pumpAndSettle();
        expect(find.text('Lịch dạy trong tuần'), findsOneWidget);
        expect(find.text('Slot 4'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'invalid import preview disables confirmation and shows row errors',
    (tester) async {
      await desktop(tester);
      final preview = ExcelImporter().parse(
        workbookFixture(
          sheets: {
            '11_PRN232_SE1917': [
              ExcelImporter.headers,
              ['SE1920', 'SE1', 'bad', 'an', 'An'],
            ],
          },
        ),
        'FA26.xlsx',
      );
      await tester.pumpWidget(
        MaterialApp(home: ImportDialog(preview: preview, replacing: false)),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Xác nhận import'),
      );
      expect(button.onPressed, isNull);
      await tester.tap(
        find.text('Kiểm tra dữ liệu (${preview.issues.length})'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Email không hợp lệ.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'valid replacement preview explains replacement and can be cancelled',
    (tester) async {
      await desktop(tester);
      final preview = ExcelImporter().parse(workbookFixture(), 'FA26.xlsx');
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => ImportDialog(preview: preview, replacing: true),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Thay dữ liệu FA26 và lưu'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(find.byType(ImportDialog), findsNothing);
    },
  );
}
