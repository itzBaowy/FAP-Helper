import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fap_helper_v1/data/qr_settings.dart';
import 'package:fap_helper_v1/domain/attendance_service.dart';
import 'package:fap_helper_v1/ui/qr_attendance_dialog.dart';
import 'package:fap_helper_v1/ui/qr_settings_panel.dart';

import 'support/attendance_fixture.dart';

void main() {
  final book = const AttendanceService().open(
    attendanceFixture(),
    'PRM393/SE1920',
    '2026-09-07/1',
    DateTime(2026, 9, 7, 8),
  );
  Future<void> mount(
    WidgetTester tester, {
    QrSettings settings = const QrSettings(),
  }) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QrAttendanceDialog(
            groupId: 'PRM393/SE1920',
            sessionId: '2026-09-07/1',
            readBook: () => book,
            onSave: (_) async {},
            loadSettings: () async => settings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'QR keeps only secret option at 800x600 and points missing ID to sidebar',
    (tester) async {
      await mount(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('QR + mã bí mật'), findsOneWidget);
      expect(find.text('Điểm danh QR · PRM393 – SE1920'), findsOneWidget);
      await tester.tap(find.text('Bắt đầu nhận QR'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Vào Cấu hình ở sidebar để nhập Google Client ID trước khi điểm danh QR.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('settings panel saves shared settings without secret option', (
    tester,
  ) async {
    QrSettings? saved;
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: QrSettingsPanel(
              loadSettings: () async => const QrSettings(
                clientId: 'test.apps.googleusercontent.com',
                connection: 'fixed',
                publicOrigin: 'https://attendance.example.com',
              ),
              saveSettings: (value) async => saved = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('QR + mã bí mật'), findsNothing);
    await tester.ensureVisible(find.text('Lưu cấu hình'));
    await tester.tap(find.text('Lưu cấu hình'));
    await tester.pumpAndSettle();
    expect(saved!.domains, {'gmail.com', 'fpt.edu.vn'});
    expect(saved!.connection, 'fixed');
    expect(saved!.publicOrigin, 'https://attendance.example.com');
    expect(
      find.text('Đã lưu. Áp dụng khi mở đợt QR tiếp theo.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  test(
    'legacy settings retain fixed origin; explicit connection survives reload',
    () async {
      final dir = await Directory.systemTemp.createTemp('qr-settings-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/qr-settings.json');
      await file.writeAsString(
        jsonEncode({
          'clientId': 'test.apps.googleusercontent.com',
          'domains': ['gmail.com', 'fpt.edu.vn'],
          'publicOrigin': 'https://attendance.example.com',
        }),
      );
      final legacy = await QrSettings.load(source: file);
      expect(legacy.connection, 'fixed');
      await QrSettings(
        clientId: legacy.clientId,
        domains: legacy.domains,
        publicOrigin: legacy.publicOrigin,
        connection: 'local',
      ).save(target: file);
      final reloaded = await QrSettings.load(source: file);
      expect(reloaded.connection, 'local');
      expect(reloaded.clientId, legacy.clientId);
      expect(reloaded.publicOrigin, legacy.publicOrigin);
    },
  );
  test('settings rejects HTTP, URL credentials, paths, empty domains and invalid ID', () {
    expect(
      () => const QrSettings(
        clientId: 'test.apps.googleusercontent.com',
        connection: 'vercel',
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const QrSettings(
        clientId: 'test.apps.googleusercontent.com',
        connection: 'vercel',
        publicOrigin: 'https://student.vercel.app',
      ).validate(),
      returnsNormally,
    );
    for (final url in [
      'http://example.com',
      'https://a:b@example.com',
      'https://example.com/a',
      'https://example.com?x=1',
    ]) {
      expect(
        () => QrSettings(
          clientId: 'test.apps.googleusercontent.com',
          publicOrigin: url,
        ).validate(),
        throwsFormatException,
      );
    }
    expect(
      () => const QrSettings(clientId: 'x').validate(),
      throwsFormatException,
    );
    expect(
      () => const QrSettings(
        clientId: 'test.apps.googleusercontent.com',
        domains: {},
      ).validate(),
      throwsFormatException,
    );
  });
}
