import 'dart:convert';
import 'dart:io';

import 'package:fap_helper_v1/data/excel_importer.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/inspect_workbook.dart <path.xlsx>');
    exitCode = 64;
    return;
  }
  final file = File(arguments.single);
  final result = ExcelImporter().parse(
    await file.readAsBytes(),
    file.uri.pathSegments.last,
  );
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'canSave': result.canSave,
      'classes': result.markbook.groups.length,
      'subjects': result.markbook.subjects,
      'enrollments': result.markbook.enrollmentCount,
      'students': result.markbook.studentCount,
      'sheets': [
        for (final group in result.markbook.groups)
          {
            'sheet': group.sheetName,
            'students': group.students.length,
            'weekdays': group.weekdays,
            'slot': group.slotNumber,
            'time': group.slot.label,
          },
      ],
      'issues': [
        for (final issue in result.issues)
          {
            'location': issue.location,
            'error': issue.isError,
            'message': issue.message,
          },
      ],
    }),
  );
  if (!result.canSave) exitCode = 1;
}
