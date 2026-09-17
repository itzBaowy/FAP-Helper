import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fap_helper_v1/data/markbook_store.dart';
import 'package:fap_helper_v1/domain/markbook.dart';

import 'support/workbook_fixture.dart';

void main() {
  late Directory temporary;
  late MarkbookStore store;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('fap_helper_store_test_');
    store = MarkbookStore(temporary);
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('first launch is empty, data survives a new store instance', () async {
    expect((await store.load()).markbook, isNull);
    await store.save(sampleBook());
    final reloaded = await MarkbookStore(temporary).load();
    expect(reloaded.markbook!.groups.length, 3);
    expect(reloaded.markbook!.studentCount, 2);
    expect(
      reloaded.markbook!.groups.first.students.first.fullName,
      'Nguyễn Văn An',
    );
    expect(reloaded.markbook!.toJson()['totalSessions'], isNull);
    expect(await File('${store.file.path}.tmp').exists(), false);
  });
  test(
    'replacement creates backup; corruption recovers previous valid data',
    () async {
      await store.save(sampleBook());
      final replacement = Markbook(
        sourceName: 'FA26_updated.xlsx',
        importedAt: DateTime.now(),
        groups: sampleBook().groups.take(1).toList(),
      );
      await store.save(replacement);
      expect((await store.load()).markbook!.groups.length, 1);
      await store.file.writeAsString('{broken');
      final recovered = await store.load();
      expect(recovered.recovered, true);
      expect(recovered.markbook!.groups.length, 3);
      await store.save(replacement);
      expect((await store.load()).markbook!.groups.length, 1);
      expect(await store.backup.readAsString(), contains('FA26_sample.xlsx'));
      expect(
        temporary
            .listSync()
            .where((entry) => entry.path.contains('.corrupt-'))
            .length,
        1,
      );
    },
  );
  test('missing primary uses backup; corrupt data without backup is not treated as empty', () async {
    await store.save(sampleBook());
    await store.save(sampleBook());
    await store.file.delete();
    expect((await store.load()).recovered, true);
    await store.backup.writeAsString('bad');
    await expectLater(store.load(), throwsFormatException);
  });
  test('invalid payload cannot overwrite valid saved data', () async {
    await store.save(sampleBook());
    final before = await store.file.readAsString();
    await expectLater(
      store.save(
        Markbook(
          sourceName: 'empty.xlsx',
          importedAt: DateTime.now(),
          groups: [],
        ),
      ),
      throwsFormatException,
    );
    expect(await store.file.readAsString(), before);
  });
}
