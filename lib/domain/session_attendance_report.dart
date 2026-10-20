import 'attendance_models.dart';
import 'markbook.dart';

enum AttendanceFilter {
  all('Tất cả'),
  present('Đã có mặt'),
  absent('Vắng'),
  unmarked('Chưa ghi nhận');

  const AttendanceFilter(this.label);
  final String label;

  bool matches(AttendanceMark? mark) => switch (this) {
    all => true,
    present => mark == AttendanceMark.present,
    absent => mark == AttendanceMark.absent,
    unmarked => mark == null,
  };
}

class SessionAttendanceEntry {
  const SessionAttendanceEntry(this.student, this.mark, this.event);
  final Student student;
  final AttendanceMark? mark;
  final AttendanceEvent? event;

  String get source => switch (event?.action) {
    'qr_present' => 'QR · Google',
    'mark' => 'Thủ công',
    'correct' => 'Sửa sau chốt',
    'close_absent' => 'Chốt buổi',
    _ => 'Không có lịch sử',
  };
}

/// A read-only view of saved marks. Audit events supply metadata, never status.
class SessionAttendanceReport {
  SessionAttendanceReport({
    required CourseGroup group,
    required CourseAttendance data,
    required AttendanceSession session,
  }) {
    final latest = <String, AttendanceEvent>{};
    for (final event in data.history) {
      // Reset retains the audit trail; older events no longer describe marks.
      if (event.action == 'reset') latest.clear();
      if (event.sessionId == session.id &&
          event.rollNumber != null &&
          const {
            'mark',
            'qr_present',
            'correct',
            'close_absent',
          }.contains(event.action)) {
        latest[event.rollNumber!] = event;
      }
    }
    entries = List.unmodifiable([
      for (final student in group.students)
        SessionAttendanceEntry(
          student,
          session.marks[student.rollNumber],
          session.marks[student.rollNumber] != null &&
                  latest[student.rollNumber]?.after ==
                      session.marks[student.rollNumber]?.code
              ? latest[student.rollNumber]
              : null,
        ),
    ]);
  }

  late final List<SessionAttendanceEntry> entries;

  int count(AttendanceFilter filter) =>
      entries.where((entry) => filter.matches(entry.mark)).length;

  List<SessionAttendanceEntry> select({
    AttendanceFilter filter = AttendanceFilter.all,
    String query = '',
    bool newestFirst = false,
  }) {
    final words = query.trim().toLowerCase().split(RegExp(r'\s+'));
    final result = entries.where((entry) {
      final student = entry.student;
      final text =
          '${student.rollNumber} ${student.fullName} '
                  '${student.email} ${student.memberCode}'
              .toLowerCase();
      return filter.matches(entry.mark) && words.every(text.contains);
    }).toList();
    result.sort((a, b) {
      if (newestFirst) {
        final left = a.event?.at;
        final right = b.event?.at;
        if (left == null && right != null) return 1;
        if (left != null && right == null) return -1;
        if (left != null && right != null) {
          final comparison = right.compareTo(left);
          if (comparison != 0) return comparison;
        }
      }
      return a.student.rollNumber.compareTo(b.student.rollNumber);
    });
    return result;
  }
}
