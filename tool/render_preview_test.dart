// Run explicitly with flutter test tool/render_preview_test.dart.
// Uses the local workbook only for a dashboard screenshot; never exports its roster.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_helper_v1/data/excel_importer.dart';
import 'package:fap_helper_v1/data/markbook_store.dart';
import 'package:fap_helper_v1/domain/markbook.dart';
import 'package:fap_helper_v1/main.dart';

class PreviewStore extends MarkbookStore {
  PreviewStore(this.book) : super(Directory('build/preview-data'));
  final Markbook book;
  @override
  Future<LoadResult> load() async => LoadResult(book);
}

void main() {
  testWidgets('render Phase 1 dashboard and weekly schedule', (tester) async {
    final source = Platform.environment['FAP_PREVIEW_WORKBOOK'];
    if (source == null) return;
    late Markbook book;
    await tester.runAsync(() async {
      final font = FontLoader('Segoe UI');
      font.addFont(
        File('C:/Windows/Fonts/segoeui.ttf')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)),
      );
      await font.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(
        File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)),
      );
      await icons.load();
      book = ExcelImporter()
          .parse(await File(source).readAsBytes(), 'FA26_Markbook.xlsx')
          .markbook;
    });
    tester.view.physicalSize = const Size(1440, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MainApp(
          store: PreviewStore(book),
          now: () => DateTime(2026, 9, 15, 10),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/previews').create(recursive: true);
        await File('build/previews/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('phase1_dashboard');
    await tester.tap(find.byTooltip('Lịch tuần').first);
    await tester.pumpAndSettle();
    await capture('phase1_week');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
