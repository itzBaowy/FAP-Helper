String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime parseDay(String value) {
  final date = DateTime.parse(value);
  if (dayKey(date) != value) {
    throw const FormatException('Ngày học không hợp lệ.');
  }
  return DateTime(date.year, date.month, date.day);
}

enum SessionState { planned, open, closed, cancelled }

enum AttendanceMark { present, absent }

extension AttendanceMarkLabel on AttendanceMark {
  String get code => this == AttendanceMark.present ? 'P' : 'A';
}

AttendanceMark parseMark(String value) => switch (value) {
  'P' => AttendanceMark.present,
  'A' => AttendanceMark.absent,
  _ => throw const FormatException('Trạng thái điểm danh không hợp lệ.'),
};

class AttendanceSession {
  AttendanceSession({
    required this.date,
    required this.slot,
    this.isMakeup = false,
    this.state = SessionState.planned,
    Map<String, AttendanceMark> marks = const {},
    this.openedAt,
    this.closedAt,
    this.note = '',
  }) : marks = Map.unmodifiable(marks) {
    if (slot < 1 || slot > 4 || date.hour != 0 || date.minute != 0) {
      throw const FormatException('Ngày hoặc slot của buổi học không hợp lệ.');
    }
  }
  final DateTime date;
  final int slot;
  final bool isMakeup;
  final SessionState state;
  final Map<String, AttendanceMark> marks;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final String note;
  String get id => '${dayKey(date)}/$slot';

  AttendanceSession copyWith({
    SessionState? state,
    Map<String, AttendanceMark>? marks,
    DateTime? openedAt,
    DateTime? closedAt,
    String? note,
  }) => AttendanceSession(
    date: date,
    slot: slot,
    isMakeup: isMakeup,
    state: state ?? this.state,
    marks: marks ?? this.marks,
    openedAt: openedAt ?? this.openedAt,
    closedAt: closedAt ?? this.closedAt,
    note: note ?? this.note,
  );

  Map<String, Object?> toJson() => {
    'date': dayKey(date),
    'slot': slot,
    'isMakeup': isMakeup,
    'state': state.name,
    'marks': marks.map((roll, mark) => MapEntry(roll, mark.code)),
    'openedAt': openedAt?.toUtc().toIso8601String(),
    'closedAt': closedAt?.toUtc().toIso8601String(),
    'note': note,
  };

  factory AttendanceSession.fromJson(Map<String, dynamic> json) =>
      AttendanceSession(
        date: parseDay(json['date'] as String),
        slot: json['slot'] as int,
        isMakeup: json['isMakeup'] as bool,
        state: SessionState.values.byName(json['state'] as String),
        marks: (json['marks'] as Map<String, dynamic>).map(
          (roll, mark) => MapEntry(roll, parseMark(mark as String)),
        ),
        openedAt: json['openedAt'] == null
            ? null
            : DateTime.parse(json['openedAt'] as String),
        closedAt: json['closedAt'] == null
            ? null
            : DateTime.parse(json['closedAt'] as String),
        note: json['note'] as String,
      );
}

class AttendanceEvent {
  const AttendanceEvent({
    required this.at,
    required this.action,
    this.sessionId,
    this.rollNumber,
    this.before,
    this.after,
    this.reason = '',
  });
  final DateTime at;
  final String action;
  final String? sessionId;
  final String? rollNumber;
  final String? before;
  final String? after;
  final String reason;
  Map<String, Object?> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'action': action,
    'sessionId': sessionId,
    'rollNumber': rollNumber,
    'before': before,
    'after': after,
    'reason': reason,
  };
  factory AttendanceEvent.fromJson(Map<String, dynamic> json) =>
      AttendanceEvent(
        at: DateTime.parse(json['at'] as String),
        action: json['action'] as String,
        sessionId: json['sessionId'] as String?,
        rollNumber: json['rollNumber'] as String?,
        before: json['before'] as String?,
        after: json['after'] as String?,
        reason: json['reason'] as String,
      );
}

class CourseAttendance {
  CourseAttendance({
    this.plannedTotal,
    List<AttendanceSession> sessions = const [],
    List<AttendanceEvent> history = const [],
  }) : sessions = List.unmodifiable(sessions),
       history = List.unmodifiable(history) {
    if (plannedTotal != null && (plannedTotal! < 1 || plannedTotal! > 200)) {
      throw const FormatException('Tổng số buổi phải từ 1 đến 200.');
    }
    if (sessions.map((session) => session.id).toSet().length !=
        sessions.length) {
      throw const FormatException('Trùng ngày và slot của buổi học.');
    }
  }
  final int? plannedTotal;
  final List<AttendanceSession> sessions;
  final List<AttendanceEvent> history;
  bool get hasData =>
      sessions.isNotEmpty || plannedTotal != null || history.isNotEmpty;
  Map<String, Object?> toJson() => {
    'plannedTotal': plannedTotal,
    'sessions': sessions.map((session) => session.toJson()).toList(),
    'history': history.map((event) => event.toJson()).toList(),
  };
  factory CourseAttendance.fromJson(Map<String, dynamic> json) =>
      CourseAttendance(
        plannedTotal: json['plannedTotal'] as int?,
        sessions: (json['sessions'] as List)
            .map(
              (s) => AttendanceSession.fromJson(
                Map<String, dynamic>.from(s as Map),
              ),
            )
            .toList(),
        history: (json['history'] as List)
            .map(
              (e) =>
                  AttendanceEvent.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(),
      );
}
