import 'package:fap_helper_v1/domain/markbook.dart';

Markbook attendanceFixture({String name = 'Nguyễn Văn An'}) => Markbook(
  sourceName: 'FA26_test.xlsx',
  importedAt: DateTime.utc(2026, 9, 1),
  groups: [
    CourseGroup(
      sheetName: '11_PRM393_SE1920',
      subjectCode: 'PRM393',
      classCode: 'SE1920',
      dayPair: 1,
      slotNumber: 1,
      students: [
        Student(
          classCode: 'SE1920',
          rollNumber: 'SE000001',
          email: 'an@example.com',
          memberCode: 'an',
          fullName: name,
        ),
        const Student(
          classCode: 'SE1920',
          rollNumber: 'SE000002',
          email: 'binh@example.com',
          memberCode: 'binh',
          fullName: 'Trần Bình',
        ),
        const Student(
          classCode: 'SE1920',
          rollNumber: 'SE000003',
          email: 'chi@example.com',
          memberCode: 'chi',
          fullName: 'Lê Chi',
        ),
      ],
    ),
  ],
);
