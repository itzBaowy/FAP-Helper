import 'package:flutter/foundation.dart';

import '../domain/markbook.dart';
import 'markbook_store.dart';

class WorkspaceConflict extends FormatException {
  const WorkspaceConflict()
    : super(
        'Dữ liệu đã thay đổi trên giao diện khác. Tải lại để đối chiếu; bản nháp chưa được ghi đè.',
      );
}

/// Native UI, teacher HTTP and QR writes share this durable, optimistic queue.
class MarkbookWorkspace extends ChangeNotifier {
  MarkbookWorkspace(this.store);
  final MarkbookStore store;
  Markbook? _book;
  int _revision = 0;
  Future<void> _tail = Future.value();
  bool _disposed = false;
  Markbook? get book => _book;
  int get revision => _revision;
  Markbook get requireBook =>
      _book ??
      (throw const FormatException(
        'Chưa có danh sách lớp. Hãy import Excel trên máy giảng viên.',
      ));

  Future<T> _serial<T>(Future<T> Function() work) {
    if (_disposed) return Future.error(StateError('Workspace is closed.'));
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _publish(Markbook? next) {
    _book = next;
    _revision++;
    if (!_disposed) notifyListeners();
  }

  Future<LoadResult> load() => _serial(() async {
    final result = await store.load();
    _publish(result.markbook);
    return result;
  });

  Future<void> replace(Markbook next, {required Markbook? expected}) =>
      _serial(() async {
        if (!identical(_book, expected)) throw const WorkspaceConflict();
        if (identical(_book, next)) return;
        await store.save(next);
        _publish(next);
      });

  Future<Markbook> change(
    Markbook Function(Markbook current) update, {
    int? expectedRevision,
  }) => _serial(() async {
    if (expectedRevision != null && expectedRevision != revision) {
      throw const WorkspaceConflict();
    }
    final current = requireBook;
    final next = update(current);
    if (!identical(current, next)) {
      await store.save(next);
      _publish(next);
    }
    return requireBook;
  });

  Future<({Markbook book, String? backupPath})> reset({String? groupId}) =>
      _serial(() async {
        final result = await store.reset(requireBook, groupId: groupId);
        if (!identical(result.book, _book)) _publish(result.book);
        return result;
      });

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
