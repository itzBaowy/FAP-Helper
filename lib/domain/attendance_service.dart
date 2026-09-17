import 'attendance_models.dart';
import 'markbook.dart';

class ScheduledSession {
  const ScheduledSession(this.session, this.number);
  final AttendanceSession session;
  final int? number;
  String get label => number == null ? 'Nghỉ' : 'Buổi $number';
}

class StudentAttendanceSummary {
  const StudentAttendanceSummary(this.present, this.absent, this.total);
  final int present;
  final int absent;
  final int? total;
  double? get absencePercent =>
      total == null || total == 0 ? null : absent * 100 / total!;
}

class AttendanceService {
  const AttendanceService();

  int regularNumber(CourseGroup group, DateTime day) {
    var count = 0;
    for (
      var date = Markbook.termStart;
      !date.isAfter(day);
      date = date.add(const Duration(days: 1))
    ) {
      if (group.weekdays.contains(date.weekday)) count++;
    }
    return count;
  }

  List<ScheduledSession> schedule(
    CourseGroup group,
    CourseAttendance data,
    DateTime through,
  ) {
    for (final session in data.sessions) {
      if (session.date.isAfter(through)) through = session.date;
    }
    final stored = {for (final s in data.sessions) s.id: s};
    final sessions = <AttendanceSession>[];
    var number = 0;
    for (
      var day = Markbook.termStart;
      data.plannedTotal == null
          ? !day.isAfter(calendarDate(through))
          : number < data.plannedTotal!;
      day = day.add(const Duration(days: 1))
    ) {
      if (!group.weekdays.contains(day.weekday)) continue;
      number++;
      final planned = AttendanceSession(date: day, slot: group.slotNumber);
      sessions.add(stored.remove(planned.id) ?? planned);
    }
    sessions.addAll(stored.values);
    sessions.sort((a, b) {
      final dates = a.date.compareTo(b.date);
      return dates != 0 ? dates : a.slot.compareTo(b.slot);
    });
    var ordinal = 0;
    return [
      for (final session in sessions)
        ScheduledSession(
          session,
          session.state == SessionState.cancelled ? null : ++ordinal,
        ),
    ];
  }

  List<ScheduledSession> onDate(
    CourseGroup group,
    CourseAttendance data,
    DateTime day,
  ) => schedule(group, data, day)
      .where(
        (s) =>
            s.session.date == calendarDate(day) &&
            s.session.state != SessionState.cancelled,
      )
      .toList();

  int? requiredTotal(CourseAttendance data) {
    if (data.plannedTotal == null) return null;
    return data.plannedTotal! -
        data.sessions
            .where((s) => !s.isMakeup && s.state == SessionState.cancelled)
            .length +
        data.sessions
            .where((s) => s.isMakeup && s.state != SessionState.cancelled)
            .length;
  }

  StudentAttendanceSummary summary(CourseAttendance data, String roll) {
    final marks = data.sessions
        .where((s) => s.state != SessionState.cancelled)
        .map((s) => s.marks[roll]);
    return StudentAttendanceSummary(
      marks.where((m) => m == AttendanceMark.present).length,
      marks.where((m) => m == AttendanceMark.absent).length,
      requiredTotal(data),
    );
  }

  bool hasStarted(AttendanceSession session, DateTime now) => !DateTime(
    session.date.year,
    session.date.month,
    session.date.day,
    TeachingSlot.all[session.slot - 1].startMinute ~/ 60,
    TeachingSlot.all[session.slot - 1].startMinute % 60,
  ).isAfter(now);

  bool isCurrent(AttendanceSession session, DateTime now) =>
      session.state != SessionState.cancelled &&
      calendarDate(now) == session.date &&
      hasStarted(session, now) &&
      now.hour * 60 + now.minute < TeachingSlot.all[session.slot - 1].endMinute;

  CourseGroup _group(Markbook book, String id) => book.groups.firstWhere(
    (g) => g.id == id,
    orElse: () => throw const FormatException('Không tìm thấy lớp học phần.'),
  );

  AttendanceSession _session(
    Markbook book,
    String id,
    String sessionId,
    DateTime now,
  ) {
    final date = parseDay(sessionId.split('/').first);
    final limit = now.add(const Duration(days: 14));
    return schedule(
          _group(book, id),
          book.attendanceFor(id),
          date.isAfter(limit) ? date : limit,
        ).where((s) => s.session.id == sessionId).firstOrNull?.session ??
        (throw const FormatException('Không tìm thấy buổi học.'));
  }

  // Receives a Vietnam wall-clock value from the UI; persist audit times in UTC.
  DateTime _auditTime(DateTime now) => DateTime.utc(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute,
    now.second,
    now.millisecond,
    now.microsecond,
  ).subtract(const Duration(hours: 7));

  Markbook _update(
    Markbook book,
    String groupId,
    AttendanceSession session,
    List<AttendanceEvent> events,
  ) {
    final data = book.attendanceFor(groupId);
    return book.withAttendance(
      groupId,
      CourseAttendance(
        plannedTotal: data.plannedTotal,
        sessions: [...data.sessions.where((s) => s.id != session.id), session],
        history: [...data.history, ...events],
      ),
    );
  }

  Markbook open(Markbook book, String groupId, String sessionId, DateTime now) {
    final session = _session(book, groupId, sessionId, now);
    if (session.state != SessionState.planned) {
      throw const FormatException('Chỉ mở được buổi chưa bắt đầu.');
    }
    if (!hasStarted(session, now)) {
      throw const FormatException('Chưa đến giờ bắt đầu buổi học.');
    }
    if (book
        .attendanceFor(groupId)
        .sessions
        .any((s) => s.state == SessionState.open)) {
      throw const FormatException(
        'Hãy chốt buổi đang mở của lớp trước khi mở buổi khác.',
      );
    }
    return _update(
      book,
      groupId,
      session.copyWith(state: SessionState.open, openedAt: _auditTime(now)),
      [
        AttendanceEvent(
          at: _auditTime(now),
          action: 'open',
          sessionId: sessionId,
        ),
      ],
    );
  }

  Markbook mark(
    Markbook book,
    String groupId,
    String sessionId,
    String roll,
    AttendanceMark? mark,
    DateTime now, {
    String reason = '',
    bool fromQr = false,
  }) {
    final group = _group(book, groupId);
    if (!group.students.any((s) => s.rollNumber == roll)) {
      throw const FormatException('Sinh viên không thuộc lớp.');
    }
    final session = _session(book, groupId, sessionId, now);
    if (![SessionState.open, SessionState.closed].contains(session.state)) {
      throw const FormatException('Cần mở buổi trước khi điểm danh.');
    }
    if (!hasStarted(session, now)) {
      throw const FormatException('Chưa đến giờ học.');
    }
    if (session.state == SessionState.closed &&
        (mark == null || reason.trim().length < 3)) {
      throw const FormatException(
        'Buổi đã chốt chỉ được sửa P/A và cần lý do ít nhất 3 ký tự.',
      );
    }
    final previous = session.marks[roll];
    if (previous == mark) return book;
    final marks = {...session.marks};
    if (mark == null) {
      marks.remove(roll);
    } else {
      marks[roll] = mark;
    }
    return _update(book, groupId, session.copyWith(marks: marks), [
      AttendanceEvent(
        at: _auditTime(now),
        action: session.state == SessionState.closed
            ? 'correct'
            : fromQr
            ? 'qr_present'
            : 'mark',
        sessionId: sessionId,
        rollNumber: roll,
        before: previous?.code,
        after: mark?.code,
        reason: reason.trim(),
      ),
    ]);
  }

  Markbook close(
    Markbook book,
    String groupId,
    String sessionId,
    DateTime now,
  ) {
    final session = _session(book, groupId, sessionId, now);
    if (session.state != SessionState.open) {
      throw const FormatException('Chỉ chốt được buổi đang mở.');
    }
    if (!hasStarted(session, now)) {
      throw const FormatException('Chưa đến giờ học.');
    }
    final marks = {...session.marks};
    final events = <AttendanceEvent>[];
    for (final student in _group(book, groupId).students) {
      if (!marks.containsKey(student.rollNumber)) {
        marks[student.rollNumber] = AttendanceMark.absent;
        events.add(
          AttendanceEvent(
            at: _auditTime(now),
            action: 'close_absent',
            sessionId: sessionId,
            rollNumber: student.rollNumber,
            after: 'A',
          ),
        );
      }
    }
    events.add(
      AttendanceEvent(
        at: _auditTime(now),
        action: 'close',
        sessionId: sessionId,
      ),
    );
    return _update(
      book,
      groupId,
      session.copyWith(
        state: SessionState.closed,
        closedAt: _auditTime(now),
        marks: marks,
      ),
      events,
    );
  }

  Markbook setTotal(Markbook book, String groupId, int? total, DateTime now) {
    final group = _group(book, groupId);
    final data = book.attendanceFor(groupId);
    if (total != null && (total < 1 || total > 200)) {
      throw const FormatException('Nhập tổng số buổi từ 1 đến 200.');
    }
    if (total != null &&
        data.sessions.any(
          (s) => !s.isMakeup && regularNumber(group, s.date) > total,
        )) {
      throw const FormatException(
        'Tổng số buổi mới sẽ loại bỏ buổi đã lưu. Hãy giữ tổng lớn hơn hoặc bằng thứ tự buổi đó trong lịch gốc.',
      );
    }
    if (data.sessions.any(
      (s) =>
          s.isMakeup &&
          s.slot == group.slotNumber &&
          group.weekdays.contains(s.date.weekday) &&
          (total == null || regularNumber(group, s.date) <= total),
    )) {
      throw const FormatException(
        'Tổng mới làm lịch tuần trùng một buổi học bù đã lưu. Hãy giữ cấu hình lịch hiện tại.',
      );
    }
    if (total == data.plannedTotal) return book;
    return book.withAttendance(
      groupId,
      CourseAttendance(
        plannedTotal: total,
        sessions: data.sessions,
        history: [
          ...data.history,
          AttendanceEvent(
            at: _auditTime(now),
            action: 'total',
            before: data.plannedTotal?.toString(),
            after: total?.toString(),
          ),
        ],
      ),
    );
  }

  Markbook cancel(
    Markbook book,
    String groupId,
    String sessionId,
    DateTime now,
    String reason,
  ) {
    final session = _session(book, groupId, sessionId, now);
    if (session.state != SessionState.planned || session.marks.isNotEmpty) {
      throw const FormatException(
        'Chỉ đánh dấu nghỉ cho buổi chưa mở, chưa có điểm danh.',
      );
    }
    if (reason.trim().length < 3) {
      throw const FormatException('Cần nhập lý do nghỉ ít nhất 3 ký tự.');
    }
    return _update(
      book,
      groupId,
      session.copyWith(state: SessionState.cancelled, note: reason.trim()),
      [
        AttendanceEvent(
          at: _auditTime(now),
          action: 'cancel',
          sessionId: sessionId,
          reason: reason.trim(),
        ),
      ],
    );
  }

  Markbook restore(
    Markbook book,
    String groupId,
    String sessionId,
    DateTime now,
  ) {
    final session = _session(book, groupId, sessionId, now);
    if (session.state != SessionState.cancelled) {
      throw const FormatException('Buổi học chưa được đánh dấu nghỉ.');
    }
    return _update(
      book,
      groupId,
      session.copyWith(state: SessionState.planned, note: ''),
      [
        AttendanceEvent(
          at: _auditTime(now),
          action: 'restore',
          sessionId: sessionId,
        ),
      ],
    );
  }

  Markbook addMakeup(
    Markbook book,
    String groupId,
    DateTime date,
    int slot,
    DateTime now,
    String reason,
  ) {
    if (date.isBefore(Markbook.termStart) || reason.trim().length < 3) {
      throw const FormatException(
        'Chọn ngày từ 07/09/2026 và nhập lý do học bù.',
      );
    }
    final day = calendarDate(date);
    final session = AttendanceSession(
      date: day,
      slot: slot,
      isMakeup: true,
      note: reason.trim(),
    );
    if (schedule(
      _group(book, groupId),
      book.attendanceFor(groupId),
      day,
    ).any((s) => s.session.id == session.id)) {
      throw const FormatException(
        'Đã có buổi ở ngày và slot này. Nếu là buổi nghỉ, hãy khôi phục buổi đó.',
      );
    }
    for (final group in book.groups) {
      if (onDate(
        group,
        book.attendanceFor(group.id),
        day,
      ).any((s) => s.session.slot == slot)) {
        throw FormatException('Trùng lịch ${group.label} ở slot $slot.');
      }
    }
    return _update(book, groupId, session, [
      AttendanceEvent(
        at: _auditTime(now),
        action: 'makeup',
        sessionId: session.id,
        reason: reason.trim(),
      ),
    ]);
  }
}
