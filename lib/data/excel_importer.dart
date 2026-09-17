import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../domain/markbook.dart';

class ImportIssue {
  const ImportIssue(this.message, {this.sheet, this.row, this.isError = true});
  final String message;
  final String? sheet;
  final int? row;
  final bool isError;
  String get location => [?sheet, if (row != null) 'Dòng $row'].join(' · ');
}

class ImportPreview {
  const ImportPreview(this.markbook, this.issues);
  final Markbook markbook;
  final List<ImportIssue> issues;
  bool get canSave =>
      markbook.groups.isNotEmpty && !issues.any((issue) => issue.isError);
  int get errorCount => issues.where((issue) => issue.isError).length;
}

class ExcelImporter {
  static const maxFileBytes = 25 * 1024 * 1024;
  static const headers = [
    'Class',
    'RollNumber',
    'Email',
    'MemberCode',
    'FullName',
  ];
  static final sheetPattern = RegExp(
    r'^([1-3])([1-4])_([A-Z][A-Z0-9]*)_([A-Z][A-Z0-9]*)$',
  );

  ImportPreview parse(Uint8List bytes, String sourceName) {
    if (bytes.length > maxFileBytes) {
      throw const FormatException('File vượt quá giới hạn 25 MB.');
    }
    if (!sourceName.toLowerCase().endsWith('.xlsx')) {
      throw const FormatException('Vui lòng chọn file Excel .xlsx.');
    }
    try {
      return _parse(bytes, sourceName);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Không đọc được cấu trúc Excel. Hãy lưu lại file dưới định dạng .xlsx và thử lại.',
      );
    }
  }

  ImportPreview _parse(Uint8List bytes, String sourceName) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.files.length > 5000 ||
        archive.files.fold<int>(0, (sum, file) => sum + file.size) >
            64 * 1024 * 1024) {
      throw const FormatException('Nội dung Excel vượt quá giới hạn xử lý.');
    }
    XmlDocument document(String path) {
      final file = archive.findFile(path);
      if (file == null) {
        throw FormatException('File Excel thiếu thành phần $path.');
      }
      return XmlDocument.parse(utf8.decode(file.content as List<int>));
    }

    final workbook = document('xl/workbook.xml');
    final relations = <String, String>{};
    for (final element in _elements(
      document('xl/_rels/workbook.xml.rels'),
      'Relationship',
    )) {
      if (element.getAttribute('TargetMode') == 'External') continue;
      final id = element.getAttribute('Id');
      final target = element.getAttribute('Target');
      if (id != null && target != null) {
        final path = Uri.parse('xl/workbook.xml').resolve(target).path;
        relations[id] = path.startsWith('/') ? path.substring(1) : path;
      }
    }
    final strings = <String>[];
    if (archive.findFile('xl/sharedStrings.xml') != null) {
      for (final item in _elements(document('xl/sharedStrings.xml'), 'si')) {
        strings.add(_elements(item, 't').map((text) => text.innerText).join());
      }
    }
    String cellValue(XmlElement cell) {
      if (cell.getAttribute('t') == 'inlineStr') {
        return _elements(cell, 't').map((text) => text.innerText).join().trim();
      }
      final raw = _elements(cell, 'v').firstOrNull?.innerText ?? '';
      if (cell.getAttribute('t') == 's') {
        final index = int.tryParse(raw);
        if (index == null || index < 0 || index >= strings.length) {
          throw const FormatException('Bảng chuỗi Excel không hợp lệ.');
        }
        return strings[index].trim();
      }
      return raw.trim();
    }

    final issues = <ImportIssue>[];
    final groups = <CourseGroup>[];
    final ids = <String>{};
    final identityEmails = <String, String>{};
    final emailOwners = <String, String>{};
    final fileTerm = RegExp(
      r'(?:^|[^A-Z0-9])((?:FA|SP|SU)\d{2})(?:[^A-Z0-9]|$)',
    ).firstMatch(sourceName.toUpperCase())?.group(1);
    if (fileTerm != null && fileTerm != Markbook.termCode) {
      issues.add(
        ImportIssue(
          'File mang mã kỳ $fileTerm. Phiên bản này chỉ quản lý FA26.',
        ),
      );
    } else if (fileTerm == null) {
      issues.add(
        const ImportIssue(
          'Tên file không có mã học kỳ. Dữ liệu sẽ được nhập vào FA26.',
          isError: false,
        ),
      );
    }

    for (final sheet in _elements(workbook, 'sheet')) {
      final name = sheet.getAttribute('name') ?? '';
      final match = sheetPattern.firstMatch(name.toUpperCase());
      if (match == null) {
        issues.add(
          ImportIssue(
            'Tên sheet phải có dạng 11_PRN232_SE1917; cặp ngày 1–3, slot 1–4.',
            sheet: name,
          ),
        );
        continue;
      }
      final subject = match.group(3)!;
      final classCode = match.group(4)!;
      if (!ids.add('$subject/$classCode')) {
        issues.add(
          ImportIssue(
            'Trùng lớp học phần $subject – $classCode ở nhiều sheet.',
            sheet: name,
          ),
        );
        continue;
      }
      final relationId = sheet.attributes
          .where((attribute) => attribute.name.local == 'id')
          .firstOrNull
          ?.value;
      final target = relations[relationId];
      if (target == null) {
        throw FormatException('Không tìm thấy dữ liệu sheet $name.');
      }
      final rows = _elements(document(target), 'row').toList();
      final columnMap = <String, String>{};
      final students = <Student>[];
      final rolls = <String>{};
      final emails = <String>{};
      var foundHeader = false;
      for (final row in rows) {
        final rowNumber = int.tryParse(row.getAttribute('r') ?? '');
        final cells = <String, XmlElement>{};
        for (final cell in row.childElements.where(
          (element) => element.name.local == 'c',
        )) {
          final address = cell.getAttribute('r') ?? '';
          cells[address.replaceAll(RegExp(r'\d'), '').toUpperCase()] = cell;
        }
        final values = cells.map(
          (column, cell) => MapEntry(column, cellValue(cell)),
        );
        if (values.values.every((value) => value.isEmpty)) continue;
        if (!foundHeader) {
          foundHeader = true;
          for (final header in headers) {
            final columns = values.entries
                .where(
                  (entry) => entry.value.toLowerCase() == header.toLowerCase(),
                )
                .toList();
            if (columns.length != 1) {
              issues.add(
                ImportIssue(
                  'Cột $header bị thiếu hoặc xuất hiện nhiều lần.',
                  sheet: name,
                  row: rowNumber,
                ),
              );
            } else {
              columnMap[header] = columns.single.key;
            }
          }
          if (columnMap.length != headers.length) break;
          continue;
        }
        final fields = {
          for (final header in headers) header: values[columnMap[header]] ?? '',
        };
        final missing = fields.entries
            .where((entry) => entry.value.isEmpty)
            .map((entry) => entry.key)
            .toList();
        if (missing.isNotEmpty) {
          issues.add(
            ImportIssue(
              'Thiếu ${missing.join(', ')}.',
              sheet: name,
              row: rowNumber,
            ),
          );
          continue;
        }
        if (columnMap.values.any(
          (column) =>
              cells[column] != null &&
              _elements(cells[column]!, 'f').isNotEmpty,
        )) {
          issues.add(
            ImportIssue(
              'Thông tin sinh viên phải là giá trị, không dùng công thức Excel.',
              sheet: name,
              row: rowNumber,
            ),
          );
          continue;
        }
        final roll = fields['RollNumber']!.toUpperCase();
        final email = fields['Email']!.toLowerCase();
        var valid = true;
        void error(String message) {
          valid = false;
          issues.add(ImportIssue(message, sheet: name, row: rowNumber));
        }

        if (fields['Class']!.toUpperCase() != classCode) {
          error('Class không khớp lớp $classCode trong tên sheet.');
        }
        if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
          error('Email không hợp lệ.');
        }
        if (!rolls.add(roll)) error('MSSV bị trùng trong sheet.');
        if (!emails.add(email)) error('Email bị trùng trong sheet.');
        if (identityEmails.containsKey(roll) && identityEmails[roll] != email) {
          error('Một MSSV có email khác nhau giữa các sheet.');
        }
        if (emailOwners.containsKey(email) && emailOwners[email] != roll) {
          error('Một email được dùng cho nhiều MSSV.');
        }
        if (!valid) continue;
        identityEmails[roll] = email;
        emailOwners[email] = roll;
        students.add(
          Student(
            classCode: classCode,
            rollNumber: roll,
            email: email,
            memberCode: fields['MemberCode']!,
            fullName: fields['FullName']!,
          ),
        );
      }
      if (!foundHeader || students.isEmpty) {
        issues.add(
          ImportIssue(
            'Sheet không có danh sách sinh viên hợp lệ.',
            sheet: name,
          ),
        );
      }
      groups.add(
        CourseGroup(
          sheetName: name,
          subjectCode: subject,
          classCode: classCode,
          dayPair: int.parse(match.group(1)!),
          slotNumber: int.parse(match.group(2)!),
          students: students,
        ),
      );
    }
    if (groups.isEmpty) {
      issues.add(const ImportIssue('Không tìm thấy lớp học phần để import.'));
    }
    final occupied = <String, String>{};
    for (final group in groups) {
      final schedule = '${group.dayPair}/${group.slotNumber}';
      if (occupied.containsKey(schedule)) {
        issues.add(
          ImportIssue(
            'Trùng giờ với ${occupied[schedule]}. Kiểm tra lại lịch dạy.',
            sheet: group.sheetName,
            isError: false,
          ),
        );
      } else {
        occupied[schedule] = group.label;
      }
    }
    groups.sort((a, b) => a.sheetName.compareTo(b.sheetName));
    return ImportPreview(
      Markbook(
        sourceName: sourceName,
        importedAt: DateTime.now(),
        groups: groups,
      ),
      issues,
    );
  }
}

Iterable<XmlElement> _elements(XmlNode node, String name) => node.descendants
    .whereType<XmlElement>()
    .where((element) => element.name.local == name);
