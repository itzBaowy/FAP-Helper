import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fap_helper_v1/data/excel_importer.dart';

import 'support/workbook_fixture.dart';

void main() {
  final importer = ExcelImporter();
  test(
    'reads shared and inline strings, Unicode and absolute relationships',
    () {
      for (final shared in [true, false]) {
        final result = importer.parse(
          workbookFixture(sharedStrings: shared, absoluteTargets: shared),
          'FA26.xlsx',
        );
        expect(result.canSave, true);
        expect(
          result.markbook.groups.single.students.single.fullName,
          'Nguyễn Văn An',
        );
        expect(result.markbook.groups.single.daysLabel, 'Thứ 2 + Thứ 5');
      }
    },
  );
  test(
    'same class in different subjects remains separate; students counted once',
    () {
      final book = sampleBook();
      expect(book.groups.length, 3);
      expect(book.subjects.length, 3);
      expect(book.enrollmentCount, 3);
      expect(book.studentCount, 2);
    },
  );
  test('matches reordered columns and skips blank rows', () {
    final result = importer.parse(
      workbookFixture(
        sheets: {
          '34_PRM323_SE1919': [
            ['', '', '', '', ''],
            ['Email', 'FullName', 'Class', 'MemberCode', 'RollNumber'],
            [' STUDENT@example.com ', 'Đặng Hà', 'se1919', 'ha', 'se000003'],
            ['', '', '', '', ''],
          ],
        },
      ),
      'FA26.xlsx',
    );
    expect(result.canSave, true);
    expect(
      result.markbook.groups.single.students.single.rollNumber,
      'SE000003',
    );
  });
  test('invalid prefix is an error, not silently omitted', () {
    final result = importer.parse(
      workbookFixture(
        sheets: {
          '45_PRM393_SE1920': [ExcelImporter.headers],
        },
      ),
      'FA26.xlsx',
    );
    expect(result.canSave, false);
    expect(result.issues.first.message, contains('Tên sheet'));
  });
  test('required header and fields block the whole import', () {
    final result = importer.parse(
      workbookFixture(
        sheets: {
          '11_PRN232_SE1917': [
            ['Class', 'RollNumber', 'Email', 'FullName'],
            ['SE1917', 'SE1', 's@example.com', 'An'],
          ],
        },
      ),
      'FA26.xlsx',
    );
    expect(result.canSave, false);
    expect(
      result.issues.any((issue) => issue.message.contains('MemberCode')),
      true,
    );
  });
  test(
    'reports mismatched class, malformed email and missing values with row',
    () {
      final result = importer.parse(
        workbookFixture(
          sheets: {
            '11_PRN232_SE1917': [
              ExcelImporter.headers,
              ['SE1920', 'SE1', 'invalid', 'an', 'An'],
              ['SE1917', 'SE2', '', 'binh', 'Bình'],
            ],
          },
        ),
        'FA26.xlsx',
      );
      expect(result.canSave, false);
      expect(result.issues.where((issue) => issue.row == 2).length, 2);
      expect(
        result.issues.any(
          (issue) => issue.row == 3 && issue.message.contains('Email'),
        ),
        true,
      );
    },
  );
  test('duplicate MSSV or email inside one sheet is rejected', () {
    final result = importer.parse(
      workbookFixture(
        sheets: {
          '11_PRN232_SE1917': [
            ExcelImporter.headers,
            ['SE1917', 'SE1', 's@example.com', 'an', 'An'],
            ['SE1917', 'se1', 'S@example.com', 'an', 'An'],
          ],
        },
      ),
      'FA26.xlsx',
    );
    expect(result.canSave, false);
    expect(
      result.issues.where((issue) => issue.message.contains('trùng')).length,
      2,
    );
  });
  test('inconsistent identity across sheets is rejected', () {
    final result = importer.parse(
      workbookFixture(
        sheets: {
          '11_PRN232_SE1917': [
            ExcelImporter.headers,
            ['SE1917', 'SE1', 'a@example.com', 'an', 'An'],
          ],
          '12_PRM393_SE1917': [
            ExcelImporter.headers,
            ['SE1917', 'SE1', 'b@example.com', 'an', 'An'],
          ],
        },
      ),
      'FA26.xlsx',
    );
    expect(result.canSave, false);
    expect(
      result.issues.any((issue) => issue.message.contains('email khác nhau')),
      true,
    );
  });
  test('duplicate course in different slots is rejected', () {
    final row = ['SE1917', 'SE1', 'a@example.com', 'an', 'An'];
    final result = importer.parse(
      workbookFixture(
        sheets: {
          '11_PRN232_SE1917': [ExcelImporter.headers, row],
          '12_PRN232_SE1917': [ExcelImporter.headers, row],
        },
      ),
      'FA26.xlsx',
    );
    expect(result.canSave, false);
  });
  test('teacher schedule collision is visible as a warning', () {
    final row = ['SE1917', 'SE1', 'a@example.com', 'an', 'An'];
    final result = importer.parse(
      workbookFixture(
        sheets: {
          '11_PRN232_SE1917': [ExcelImporter.headers, row],
          '11_PRM393_SE1917': [ExcelImporter.headers, row],
        },
      ),
      'FA26.xlsx',
    );
    expect(result.canSave, true);
    expect(result.issues.single.isError, false);
  });
  test('does not execute or trust formulas in identity fields', () {
    expect(
      importer.parse(workbookFixture(formula: true), 'FA26.xlsx').canSave,
      false,
    );
  });
  test('wrong term and corrupt file are rejected', () {
    expect(
      importer.parse(workbookFixture(), 'SP26_Markbook.xlsx').canSave,
      false,
    );
    expect(
      () => importer.parse(Uint8List.fromList([1, 2, 3]), 'FA26.xlsx'),
      throwsFormatException,
    );
    expect(
      () => importer.parse(workbookFixture(), 'FA26.xls'),
      throwsFormatException,
    );
  });
}
