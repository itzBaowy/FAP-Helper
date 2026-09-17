import 'dart:convert';
import 'dart:io';

import '../domain/markbook.dart';
import '../domain/attendance_reset.dart';

class LoadResult {
  const LoadResult(this.markbook, {this.recovered = false});
  final Markbook? markbook;
  final bool recovered;
}

class MarkbookStore {
  MarkbookStore(this.directory);
  final Directory directory;

  factory MarkbookStore.forWindows() {
    final override = Platform.environment['FAP_HELPER_DATA_DIR'];
    if (override != null && override.isNotEmpty) {
      return MarkbookStore(Directory(override));
    }
    final root = Platform.environment['APPDATA'];
    if (root == null || root.isEmpty) {
      throw const FileSystemException(
        'Không tìm thấy thư mục dữ liệu người dùng Windows.',
      );
    }
    return MarkbookStore(Directory('$root${Platform.pathSeparator}FAPHelper'));
  }

  File get file => File('${directory.path}${Platform.pathSeparator}FA26.json');
  File get backup => File('${file.path}.bak');

  Future<Markbook> _read(File target) async => Markbook.fromJson(
    jsonDecode(await target.readAsString()) as Map<String, dynamic>,
  );

  Future<LoadResult> load() async {
    final exists = await file.exists();
    if (!exists && !await backup.exists()) return const LoadResult(null);
    try {
      return LoadResult(await _read(file));
    } catch (_) {
      if (await backup.exists()) {
        try {
          return LoadResult(await _read(backup), recovered: true);
        } catch (_) {
          // Leave both files untouched for manual recovery.
        }
      }
      throw const FormatException(
        'Không đọc được dữ liệu đã lưu. Hãy kiểm tra FA26.json và bản sao .bak trước khi tiếp tục.',
      );
    }
  }

  Future<void> save(Markbook markbook) async {
    // Validate the exact payload before touching any previous data.
    final payload = const JsonEncoder.withIndent('  ')
        .convert(markbook.toJson());
    Markbook.fromJson(jsonDecode(payload) as Map<String, dynamic>);
    await directory.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(payload, flush: true);
    if (await file.exists()) {
      var valid = false;
      try {
        await _read(file);
        valid = true;
      } catch (_) {
        // Never replace a healthy backup with corrupt data.
      }
      if (valid) {
        final backupTemporary = await file.copy('${backup.path}.tmp');
        await backupTemporary.rename(backup.path);
      } else {
        await file.copy(
          '${file.path}.corrupt-${DateTime.now().microsecondsSinceEpoch}',
        );
      }
    }
    await temporary.rename(file.path);
  }

  /// Keep a permanent snapshot, independently of the rolling .bak file.
  Future<({Markbook book, String? backupPath})> reset(
    Markbook current, {
    String? groupId,
  }) async {
    final updated = resetAttendance(current, groupId: groupId);
    if (identical(updated, current)) return (book: current, backupPath: null);
    final payload = const JsonEncoder.withIndent('  ')
        .convert(current.toJson());
    Markbook.fromJson(jsonDecode(payload) as Map<String, dynamic>);
    Markbook.fromJson(updated.toJson());
    final backups = Directory(
      '${directory.path}${Platform.pathSeparator}backups',
    );
    await backups.create(recursive: true);
    final snapshot = File(
      '${backups.path}${Platform.pathSeparator}FA26-before-reset-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    await snapshot.writeAsString(payload, flush: true);
    await _read(snapshot);
    await save(updated);
    return (book: updated, backupPath: snapshot.path);
  }
}
