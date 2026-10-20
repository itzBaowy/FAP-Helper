// Fixture-only host for tool/end_to_end_browser_smoke.mjs; no real user data.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fap_helper_v1/data/google_identity.dart';
import 'package:fap_helper_v1/data/markbook_store.dart';
import 'package:fap_helper_v1/data/markbook_workspace.dart';
import 'package:fap_helper_v1/data/qr_collection.dart';
import 'package:fap_helper_v1/data/qr_settings.dart';
import 'package:fap_helper_v1/data/teacher_workspace_host.dart';
import 'package:fap_helper_v1/domain/attendance_service.dart';
import 'package:fap_helper_v1/domain/markbook.dart';

import '../test/support/attendance_fixture.dart';

class _BrowserIdentity implements IdentityVerifier {
  @override
  Future<GoogleIdentity> verify(String credential, String nonce) async =>
      GoogleIdentity(credential, 'browser-fixture');
  @override
  void dispose() {}
}

void main() {
  test(
    'fixture host for the complete teacher and student browser workflow',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fap-e2e-fixture-',
      );
      final metadata = File('build/e2e-host.json'),
          stop = File('build/e2e-stop');
      if (await metadata.exists()) await metadata.delete();
      if (await stop.exists()) await stop.delete();
      final workspace = MarkbookWorkspace(MarkbookStore(directory));
      await workspace.replace(
        const AttendanceService().open(
          attendanceFixture(),
          'PRM393/SE1920',
          '2026-09-07/1',
          vietnamNow(),
        ),
        expected: null,
      );
      Future<Map<String, String>> pages(
        String source,
        List<String> names,
      ) async => {
        for (final name in names)
          name == 'index.html' ? '/' : '/$name': await File('$source/$name')
              .readAsString(),
      };
      final collection = QrCollection(
        readBook: () => workspace.requireBook,
        saveBook: (book) => workspace.replace(book, expected: workspace.book),
        loadAssets: () =>
            pages('assets/student', ['index.html', 'app.js', 'style.css']),
        loadSettings: () async => const QrSettings(
          clientId: 'fixture.apps.googleusercontent.com',
          connection: 'local',
        ),
        createVerifier: (_) => _BrowserIdentity(),
        port: 0,
      );
      final host = TeacherWorkspaceHost(
        workspace: workspace,
        collection: collection,
        assets: await pages('mock-fap/public', [
          'index.html',
          'app.mjs',
          'connection.mjs',
          'xlsx-importer.mjs',
          'style.css',
          'workspace.mjs',
          'reports.mjs',
        ]),
      );
      try {
        await host.start();
        await metadata.writeAsString(
          jsonEncode({
            'origin': host.localOrigin,
            'link': host.browserLink(),
            'key': host.accessKey,
          }),
        );
        stdout.writeln(
          'E2E fixture ready; no real roster or Google account is used.',
        );
        while (!await stop.exists()) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        await File('build/e2e-persisted.json')
            .writeAsString(jsonEncode(workspace.requireBook.toJson()));
      } finally {
        await host.stop();
        await collection.stop(immediate: true);
        collection.dispose();
        workspace.dispose();
        await directory.delete(recursive: true);
        if (await metadata.exists()) await metadata.delete();
        if (await stop.exists()) await stop.delete();
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
