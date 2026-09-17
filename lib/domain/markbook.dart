import 'attendance_models.dart';

DateTime calendarDate(DateTime value) =>
    DateTime(value.year, value.month, value.day);

// A wall-clock value in Vietnam, independent of the Windows time zone.
DateTime vietnamNow() {
  final utc = DateTime.now().toUtc().add(const Duration(hours: 7));
  return DateTime(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
  );
}

String dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String weekdayLabel(int weekday) =>
    weekday == 7 ? 'Chủ nhật' : 'Thứ ${weekday + 1}';

class TeachingSlot {
  const TeachingSlot(this.number, this.startMinute, this.endMinute);
  final int number;
  final int startMinute;
  final int endMinute;

  static const all = [
    TeachingSlot(1, 450, 555),
    TeachingSlot(2, 570, 705),
    TeachingSlot(3, 750, 885),
    TeachingSlot(4, 900, 1035),
  ];

  static String timeLabel(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  String get label => '${timeLabel(startMinute)} – ${timeLabel(endMinute)}';
}

class Student {
  const Student({
    required this.classCode,
    required this.rollNumber,
    required this.email,
    required this.memberCode,
    required this.fullName,
  });
  final String classCode;
  final String rollNumber;
  final String email;
  final String memberCode;
  final String fullName;

  Map<String, Object?> toJson() => {
    'classCode': classCode,
    'rollNumber': rollNumber,
    'email': email,
    'memberCode': memberCode,
    'fullName': fullName,
  };

  factory Student.fromJson(Map<String, dynamic> json) => Student(
    classCode: requiredText(json, 'classCode'),
    rollNumber: requiredText(json, 'rollNumber'),
    email: requiredText(json, 'email'),
    memberCode: requiredText(json, 'memberCode'),
    fullName: requiredText(json, 'fullName'),
  );
}

class CourseGroup {
  CourseGroup({
    required this.sheetName,
    required this.subjectCode,
    required this.classCode,
    required this.dayPair,
    required this.slotNumber,
    required List<Student> students,
  }) : students = List.unmodifiable(students) {
    if (dayPair < 1 || dayPair > 3 || slotNumber < 1 || slotNumber > 4) {
      throw const FormatException('Lịch học không hợp lệ.');
    }
  }

  final String sheetName;
  final String subjectCode;
  final String classCode;
  final int dayPair;
  final int slotNumber;
  final List<Student> students;

  String get id => '$subjectCode/$classCode';
  String get label => '$subjectCode – $classCode';
  List<int> get weekdays => [dayPair, dayPair + 3];
  String get daysLabel => weekdays.map(weekdayLabel).join(' + ');
  TeachingSlot get slot => TeachingSlot.all[slotNumber - 1];

  bool meetsOn(DateTime day, DateTime termStart) =>
      !calendarDate(day).isBefore(calendarDate(termStart)) &&
      weekdays.contains(day.weekday);

  DateTime firstMeeting(DateTime termStart) {
    var day = calendarDate(termStart);
    while (!weekdays.contains(day.weekday)) {
      day = day.add(const Duration(days: 1));
    }
    return day;
  }

  bool isCurrent(DateTime now, DateTime termStart) {
    final minute = now.hour * 60 + now.minute;
    return meetsOn(now, termStart) &&
        minute >= slot.startMinute &&
        minute < slot.endMinute;
  }

  Map<String, Object?> toJson() => {
    'sheetName': sheetName,
    'subjectCode': subjectCode,
    'classCode': classCode,
    'dayPair': dayPair,
    'slotNumber': slotNumber,
    'students': students.map((student) => student.toJson()).toList(),
  };

  factory CourseGroup.fromJson(Map<String, dynamic> json) => CourseGroup(
    sheetName: requiredText(json, 'sheetName'),
    subjectCode: requiredText(json, 'subjectCode'),
    classCode: requiredText(json, 'classCode'),
    dayPair: json['dayPair'] as int,
    slotNumber: json['slotNumber'] as int,
    students: (json['students'] as List)
        .map((row) => Student.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList(),
  );
}

class Markbook {
  Markbook({
    required this.sourceName,
    required this.importedAt,
    required List<CourseGroup> groups,
    Map<String, CourseAttendance> attendance = const {},
  }) : groups = List.unmodifiable(groups),
       attendance = Map.unmodifiable(attendance);

  static const termCode = 'FA26';
  static final termStart = DateTime(2026, 9, 7);
  final String sourceName;
  final DateTime importedAt;
  final List<CourseGroup> groups;
  final Map<String, CourseAttendance> attendance;

  CourseAttendance attendanceFor(String groupId) =>
      attendance[groupId] ?? CourseAttendance();

  Markbook withAttendance(String groupId, CourseAttendance value) => Markbook(
    sourceName: sourceName,
    importedAt: importedAt,
    groups: groups,
    attendance: {...attendance, groupId: value},
  );

  // Re-import may refresh identity details but must not erase or reinterpret
  // attendance. Roster or schedule changes for an active course need a future
  // enrollment migration workflow, so those imports are rejected explicitly.
  Markbook mergeImport(Markbook incoming) {
    for (final old in groups) {
      if (!attendanceFor(old.id).hasData) continue;
      final next = incoming.groups.where((g) => g.id == old.id).firstOrNull;
      final oldRolls = old.students.map((s) => s.rollNumber).toSet();
      if (next == null ||
          next.dayPair != old.dayPair ||
          next.slotNumber != old.slotNumber ||
          next.students.length != old.students.length ||
          next.students.any((s) => !oldRolls.contains(s.rollNumber))) {
        throw FormatException(
          '${old.label} đã có dữ liệu điểm danh/cấu hình. Không thể xóa lớp, đổi lịch hoặc thêm/bớt MSSV bằng import. Dữ liệu hiện tại được giữ nguyên.',
        );
      }
    }
    return Markbook(
      sourceName: incoming.sourceName,
      importedAt: incoming.importedAt,
      groups: incoming.groups,
      attendance: attendance,
    );
  }

  List<String> get subjects =>
      (groups.map((group) => group.subjectCode).toSet().toList()..sort());
  int get enrollmentCount =>
      groups.fold(0, (sum, group) => sum + group.students.length);
  int get studentCount => groups
      .expand((group) => group.students)
      .map((student) => student.rollNumber)
      .toSet()
      .length;

  List<CourseGroup> onDate(DateTime date) =>
      groups.where((group) => group.meetsOn(date, termStart)).toList()
        ..sort((a, b) => a.slotNumber.compareTo(b.slotNumber));

  Map<String, Object?> toJson() => {
    'schemaVersion': 2,
    'termCode': termCode,
    'termStart': '2026-09-07',
    'termEnd': null,
    'totalSessions': null,
    'sourceName': sourceName,
    'importedAt': importedAt.toUtc().toIso8601String(),
    'groups': groups.map((group) => group.toJson()).toList(),
    'attendance': attendance.map((id, value) => MapEntry(id, value.toJson())),
  };

  factory Markbook.fromJson(Map<String, dynamic> json) {
    if (![1, 2].contains(json['schemaVersion']) ||
        json['termCode'] != termCode ||
        json['termStart'] != '2026-09-07') {
      throw const FormatException(
        'Dữ liệu không đúng phiên bản hoặc học kỳ FA26.',
      );
    }
    final groups = (json['groups'] as List)
        .map(
          (row) => CourseGroup.fromJson(Map<String, dynamic>.from(row as Map)),
        )
        .toList();
    if (groups.isEmpty ||
        groups.map((group) => group.id).toSet().length != groups.length) {
      throw const FormatException('Danh sách lớp học phần không hợp lệ.');
    }
    for (final group in groups) {
      final rolls = <String>{};
      final emails = <String>{};
      if (group.students.isEmpty) {
        throw const FormatException('Lớp không có sinh viên.');
      }
      for (final student in group.students) {
        if (student.classCode != group.classCode ||
            !rolls.add(student.rollNumber) ||
            !emails.add(student.email.toLowerCase())) {
          throw const FormatException('Danh sách sinh viên không hợp lệ.');
        }
      }
    }
    final attendance = json['schemaVersion'] == 1
        ? <String, CourseAttendance>{}
        : (json['attendance'] as Map<String, dynamic>).map(
            (id, value) => MapEntry(
              id,
              CourseAttendance.fromJson(
                Map<String, dynamic>.from(value as Map),
              ),
            ),
          );
    for (final entry in attendance.entries) {
      final group = groups.where((g) => g.id == entry.key).firstOrNull;
      if (group == null) {
        throw const FormatException('Điểm danh không thuộc lớp nào trong kỳ.');
      }
      final rolls = group.students.map((s) => s.rollNumber).toSet();
      if (entry.value.sessions
              .where((s) => s.state == SessionState.open)
              .length >
          1) {
        throw const FormatException('Một lớp có nhiều buổi đang mở.');
      }
      for (final session in entry.value.sessions) {
        final first = group.firstMeeting(termStart);
        final regularOrdinal =
            session.date.difference(first).inDays ~/ 7 * 2 +
            (session.date.weekday == group.dayPair ? 1 : 2);
        final onRegularSlot =
            group.weekdays.contains(session.date.weekday) &&
            session.slot == group.slotNumber;
        if (session.date.isBefore(termStart) ||
            (!session.isMakeup &&
                entry.value.plannedTotal != null &&
                regularOrdinal > entry.value.plannedTotal!) ||
            (session.isMakeup &&
                onRegularSlot &&
                (entry.value.plannedTotal == null ||
                    regularOrdinal <= entry.value.plannedTotal!)) ||
            session.marks.keys.any((roll) => !rolls.contains(roll)) ||
            (session.state == SessionState.closed &&
                (session.closedAt == null ||
                    session.marks.length != rolls.length)) ||
            ([SessionState.open, SessionState.closed].contains(session.state) &&
                session.openedAt == null) ||
            ([
                  SessionState.planned,
                  SessionState.cancelled,
                ].contains(session.state) &&
                session.marks.isNotEmpty) ||
            (session.state != SessionState.closed &&
                session.closedAt != null) ||
            (!session.isMakeup &&
                (!group.weekdays.contains(session.date.weekday) ||
                    session.slot != group.slotNumber))) {
          throw const FormatException('Dữ liệu buổi điểm danh không hợp lệ.');
        }
      }
    }
    return Markbook(
      sourceName: requiredText(json, 'sourceName'),
      importedAt: DateTime.parse(requiredText(json, 'importedAt')),
      groups: groups,
      attendance: attendance,
    );
  }
}

String requiredText(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Thiếu trường $key.');
  }
  return value;
}
