import 'attendance_models.dart';
import 'markbook.dart';

bool hasAttendanceToReset(CourseAttendance data) => data.sessions.any(
  (s) =>
      s.marks.isNotEmpty ||
      s.openedAt != null ||
      s.closedAt != null ||
      s.state == SessionState.open ||
      s.state == SessionState.closed,
);

Markbook resetAttendance(Markbook book, {String? groupId}) {
  if (groupId != null && !book.groups.any((g) => g.id == groupId)) {
    throw const FormatException('Lớp học phần không tồn tại.');
  }
  var result = book;
  for (final group in book.groups) {
    if (groupId != null && group.id != groupId) continue;
    final data = book.attendanceFor(group.id);
    if (!hasAttendanceToReset(data)) continue;
    result = result.withAttendance(
      group.id,
      CourseAttendance(
        plannedTotal: data.plannedTotal,
        sessions: [
          for (final s in data.sessions)
            AttendanceSession(
              date: s.date,
              slot: s.slot,
              isMakeup: s.isMakeup,
              note: s.note,
              state: s.state == SessionState.cancelled
                  ? SessionState.cancelled
                  : SessionState.planned,
            ),
        ],
        history: [
          ...data.history,
          AttendanceEvent(
            at: DateTime.now().toUtc(),
            action: 'reset',
            reason: groupId == null
                ? 'Reset toàn bộ kỳ FA26'
                : 'Reset lớp học phần',
          ),
        ],
      ),
    );
  }
  return result;
}
