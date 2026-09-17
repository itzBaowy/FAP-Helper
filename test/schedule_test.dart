import 'package:flutter_test/flutter_test.dart';
import 'package:fap_helper_v1/domain/markbook.dart';

void main() {
  CourseGroup group(int pair, int slot) => CourseGroup(
    sheetName: '$pair${slot}_PRM393_SE1920',
    subjectCode: 'PRM393',
    classCode: 'SE1920',
    dayPair: pair,
    slotNumber: slot,
    students: [],
  );

  test('first meetings follow the actual weekday, not all Monday', () {
    for (var pair = 1; pair <= 3; pair++) {
      expect(
        group(pair, 1).firstMeeting(Markbook.termStart),
        DateTime(2026, 9, 6 + pair),
      );
    }
  });
  test('no meetings before term start or on Sunday', () {
    expect(
      group(1, 1).meetsOn(DateTime(2026, 8, 31), Markbook.termStart),
      false,
    );
    expect(
      group(1, 1).meetsOn(DateTime(2026, 9, 13), Markbook.termStart),
      false,
    );
    expect(
      group(1, 1).meetsOn(DateTime(2026, 9, 10), Markbook.termStart),
      true,
    );
  });
  test('all four slots use exact approved start/end times', () {
    const expected = [(450, 555), (570, 705), (750, 885), (900, 1035)];
    for (var index = 0; index < 4; index++) {
      final course = group(1, index + 1);
      final (start, end) = expected[index];
      DateTime at(int minute) =>
          DateTime(2026, 9, 7, minute ~/ 60, minute % 60);
      expect(course.isCurrent(at(start - 1), Markbook.termStart), false);
      expect(course.isCurrent(at(start), Markbook.termStart), true);
      expect(course.isCurrent(at(end - 1), Markbook.termStart), true);
      expect(course.isCurrent(at(end), Markbook.termStart), false);
      expect(
        course.isCurrent(
          DateTime(2026, 9, 8, start ~/ 60, start % 60),
          Markbook.termStart,
        ),
        false,
      );
    }
  });
}
