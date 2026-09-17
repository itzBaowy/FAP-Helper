import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fap_helper_v1/data/excel_importer.dart';
import 'package:fap_helper_v1/domain/markbook.dart';

String escaped(String value) => const HtmlEscape().convert(value);

Uint8List workbookFixture({
  Map<String, List<List<String>>>? sheets,
  bool sharedStrings = false,
  bool formula = false,
  bool absoluteTargets = false,
}) {
  sheets ??= {
    '11_PRN232_SE1917': [
      ExcelImporter.headers,
      [
        'SE1917',
        'SE000001',
        'student1@example.com',
        'student1',
        'Nguyễn Văn An',
      ],
    ],
  };
  final archive = Archive();
  void add(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  final names = sheets.keys.toList();
  const namespace = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const relationshipNamespace =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  add(
    '[Content_Types].xml',
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${[for (var i = 0; i < names.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}</Types>',
  );
  add(
    '_rels/.rels',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="$relationshipNamespace/officeDocument" Target="xl/workbook.xml"/></Relationships>',
  );
  add(
    'xl/workbook.xml',
    '<workbook xmlns="$namespace" xmlns:r="$relationshipNamespace"><sheets>${[for (var i = 0; i < names.length; i++) '<sheet name="${escaped(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}</sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${[for (var i = 0; i < names.length; i++) '<Relationship Id="rId${i + 1}" Target="${absoluteTargets ? '/xl/' : ''}worksheets/sheet${i + 1}.xml" Type="$relationshipNamespace/worksheet"/>'].join()}</Relationships>',
  );
  final strings = <String>[];
  for (var index = 0; index < names.length; index++) {
    final rows = sheets[names[index]]!;
    final xmlRows = <String>[];
    for (var row = 0; row < rows.length; row++) {
      final cells = <String>[];
      for (var col = 0; col < rows[row].length; col++) {
        final value = rows[row][col];
        final address = '${String.fromCharCode(65 + col)}${row + 1}';
        final expression = formula && row == 1 && col == 1
            ? '<f>"SE000001"</f>'
            : '';
        if (sharedStrings) {
          strings.add(value);
          cells.add(
            '<c r="$address" t="s">$expression<v>${strings.length - 1}</v></c>',
          );
        } else {
          cells.add(
            '<c r="$address" t="inlineStr">$expression<is><t>${escaped(value)}</t></is></c>',
          );
        }
      }
      xmlRows.add('<row r="${row + 1}">${cells.join()}</row>');
    }
    add(
      'xl/worksheets/sheet${index + 1}.xml',
      '<worksheet xmlns="$namespace"><sheetData>${xmlRows.join()}</sheetData></worksheet>',
    );
  }
  if (sharedStrings) {
    add(
      'xl/sharedStrings.xml',
      '<sst xmlns="$namespace">${strings.map((s) => '<si><t>${escaped(s)}</t></si>').join()}</sst>',
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

Markbook sampleBook() => ExcelImporter()
    .parse(
      workbookFixture(
        sheets: {
          '11_PRN232_SE1917': [
            ExcelImporter.headers,
            [
              'SE1917',
              'SE000001',
              'student1@example.com',
              'student1',
              'Nguyễn Văn An',
            ],
          ],
          '12_PRM393_SE1917': [
            ExcelImporter.headers,
            [
              'SE1917',
              'SE000001',
              'student1@example.com',
              'student1',
              'Nguyễn Văn An',
            ],
          ],
          '23_SWD392_SE1927': [
            ExcelImporter.headers,
            [
              'SE1927',
              'SE000002',
              'student2@example.com',
              'student2',
              'Trần Bình',
            ],
          ],
        },
      ),
      'FA26_sample.xlsx',
    )
    .markbook;
