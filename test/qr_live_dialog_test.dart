import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fap_helper_v1/data/google_identity.dart';
import 'package:fap_helper_v1/data/qr_settings.dart';
import 'package:fap_helper_v1/domain/attendance_service.dart';
import 'package:fap_helper_v1/ui/qr_attendance_dialog.dart';

import 'support/attendance_fixture.dart';

class _FixtureIdentity implements IdentityVerifier {
  @override
  Future<GoogleIdentity> verify(String credential, String nonce) async =>
      const GoogleIdentity('an@example.com', 'fixture-user');
  @override
  void dispose() {}
}

// Use real localhost HTTP in this integration test, bypassing Flutter's mock.
class _LocalHttp extends HttpOverrides {}

void main() {
  testWidgets(
    'live QR roster reflects durable HTTP saves once and can hide names',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var book = const AttendanceService().open(
        attendanceFixture(),
        'PRM393/SE1920',
        '2026-09-07/1',
        DateTime(2026, 9, 7, 8),
      );
      var failSave = true;
      var saves = 0;
      Completer<void>? entered;
      Completer<void>? release;
      addTearDown(() {
        if (release != null && !release!.isCompleted) release!.complete();
      });
      final preview = Platform.environment['FAP_ATTENDANCE_PREVIEW'] == '1';
      final boundary = GlobalKey();
      if (preview) {
        await tester.runAsync(() async {
          for (final entry in {
            'Segoe UI': 'C:/Windows/Fonts/segoeui.ttf',
            'MaterialIcons':
                'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
          }.entries) {
            final font = FontLoader(entry.key)
              ..addFont(
                File(entry.value).readAsBytes().then(ByteData.sublistView),
              );
            await font.load();
          }
        });
      }
      Future<void> capture(String name) async {
        if (!preview) return;
        final renderer =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await renderer.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/previews').create(recursive: true);
          await File('build/previews/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'Segoe UI',
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xff16786b),
                primary: const Color(0xff16786b),
                surface: Colors.white,
                onSurface: const Color(0xff163c3a),
              ),
            ),
            home: Scaffold(
              body: QrAttendanceDialog(
                groupId: 'PRM393/SE1920',
                sessionId: '2026-09-07/1',
                readBook: () => book,
                loadSettings: () async => const QrSettings(
                  clientId: 'test.apps.googleusercontent.com',
                  connection: 'local',
                ),
                createVerifier: (_) => _FixtureIdentity(),
                onSave: (next) async {
                  if (failSave) throw const FileSystemException('Disk full');
                  entered?.complete();
                  await release?.future;
                  book = next;
                  saves++;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Bắt đầu nhận QR'),
            )
            .onPressed!();
      });
      for (
        var attempt = 0;
        attempt < 50 && find.byType(QrImageView).evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      await tester.tap(find.text('Sao chép liên kết QR hiện tại'));
      await tester.pump();
      final url = Uri.parse(copied!);
      final client = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        _LocalHttp(),
      );
      addTearDown(() => client.close(force: true));
      Future<Map<String, dynamic>> post(
        String path,
        Map<String, String> body, {
        int status = 200,
      }) async {
        final request = await client.postUrl(Uri.parse('${url.origin}$path'));
        request.headers.set('Origin', url.origin);
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
        final response = await request.close().timeout(
          const Duration(seconds: 5),
        );
        expect(response.statusCode, status);
        return jsonDecode(await utf8.decoder.bind(response).join())
            as Map<String, dynamic>;
      }

      final scan = await tester.runAsync(
        () => post('/api/scan', {'token': url.fragment}),
      );
      final ticket = scan!['ticket'] as String;
      await tester.runAsync(
        () => post('/api/login', {'ticket': ticket, 'credential': 'fixture'}),
      );
      await tester.runAsync(
        () =>
            post('/api/submit', {'ticket': ticket, 'secret': ''}, status: 503),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('qr-attendee-SE000001')), findsNothing);
      expect(saves, 0);
      failSave = false;
      late Future<Map<String, dynamic>> pending;
      await tester.runAsync(() async {
        entered = Completer<void>();
        release = Completer<void>();
        pending = post('/api/submit', {'ticket': ticket, 'secret': ''});
        await entered!.future.timeout(const Duration(seconds: 5));
      });
      await tester.pump();
      expect(find.byKey(const ValueKey('qr-attendee-SE000001')), findsNothing);
      await tester.runAsync(() async {
        release!.complete();
        await pending;
      });
      await tester.pump();
      expect(find.text('Nguyễn Văn An'), findsOneWidget);
      expect(find.textContaining('QR · Google'), findsOneWidget);
      final duplicate = await tester.runAsync(
        () => post('/api/submit', {'ticket': ticket, 'secret': ''}),
      );
      expect(duplicate!['duplicate'], true);
      await tester.pump();
      expect(saves, 1);
      expect(
        find.byKey(const ValueKey('qr-attendee-SE000001')),
        findsOneWidget,
      );
      expect(
        book
            .attendanceFor('PRM393/SE1920')
            .history
            .where((e) => e.action == 'qr_present')
            .length,
        1,
      );
      await capture('attendance-live-wide');
      tester.view.physicalSize = const Size(800, 600);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('qr-attendee-SE000001')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture('attendance-live-800x600');
      tester.view.physicalSize = const Size(1280, 900);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('qr-filter-unmarked')));
      await tester.pumpAndSettle();
      expect(find.text('Nguyễn Văn An'), findsNothing);
      expect(find.text('Trần Bình'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('qr-roster-search')),
        'chi@example.com',
      );
      await tester.pumpAndSettle();
      expect(find.text('Trần Bình'), findsNothing);
      expect(find.text('Lê Chi'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('show-qr-roster')));
      await tester.pumpAndSettle();
      expect(find.text('Lê Chi'), findsNothing);
      expect(find.byKey(const ValueKey('qr-roster-search')), findsNothing);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    },
  );
}
