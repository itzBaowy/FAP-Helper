import 'dart:convert';
import 'dart:io';

import '../domain/attendance_models.dart';
import '../domain/attendance_service.dart';
import '../domain/markbook.dart';

class AttendanceCsv {
  static const headers = [
    'SchemaVersion',
    'Term',
    'SubjectCode',
    'ClassCode',
    'SessionId',
    'SessionNumber',
    'Date',
    'Slot',
    'StartTime',
    'EndTime',
    'RollNumber',
    'Email',
    'FullName',
    'MemberCode',
    'Status',
    'ClosedAt',
    'ExportedAt',
  ];

  String generate(
    Markbook book,
    String groupId,
    DateTime exportedAt, {
    String? sessionId,
  }) {
    final group = book.groups.firstWhere((g) => g.id == groupId);
    final data = book.attendanceFor(groupId);
    final sessions = const AttendanceService()
        .schedule(group, data, Markbook.termStart)
        .where(
          (s) =>
              s.session.state == SessionState.closed &&
              (sessionId == null || s.session.id == sessionId),
        )
        .toList();
    if (sessions.isEmpty) {
      throw const FormatException('Chỉ xuất CSV của buổi đã chốt.');
    }
    final rows = <List<String>>[headers];
    for (final scheduled in sessions) {
      final session = scheduled.session;
      final slot = TeachingSlot.all[session.slot - 1];
      for (final student in group.students) {
        final mark = session.marks[student.rollNumber];
        if (mark == null || session.closedAt == null) {
          throw const FormatException(
            'Buổi đã chốt còn thiếu kết quả điểm danh.',
          );
        }
        rows.add([
          '1',
          Markbook.termCode,
          group.subjectCode,
          group.classCode,
          '${Markbook.termCode}/$groupId/${session.id}',
          '${scheduled.number}',
          dayKey(session.date),
          '${session.slot}',
          TeachingSlot.timeLabel(slot.startMinute),
          TeachingSlot.timeLabel(slot.endMinute),
          student.rollNumber,
          student.email,
          student.fullName,
          student.memberCode,
          mark.code,
          session.closedAt!.toUtc().toIso8601String(),
          exportedAt.toUtc().toIso8601String(),
        ]);
      }
    }
    return '\ufeff${rows.map((row) => row.map(_cell).join(',')).join('\r\n')}\r\n';
  }

  // Excel must display imported text as data, including names beginning with =.
  String _cell(String text) {
    if (RegExp(r'^\s*[=+\-@]').hasMatch(text) ||
        text.startsWith('\t') ||
        text.startsWith('\r')) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }

  Future<void> save(String path, String content) async {
    if (!path.toLowerCase().endsWith('.csv')) {
      throw const FormatException('Tên file phải có đuôi .csv.');
    }
    final target = File(path);
    final temporary = File(
      '$path.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsBytes(utf8.encode(content), flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
