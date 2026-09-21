import {test} from 'node:test';
import assert from 'node:assert/strict';
import {deflateRawSync} from 'node:zlib';
import {parseXlsx} from '../mock-fap/public/xlsx-importer.mjs';
import {importMarkbook} from '../mock-fap/model.mjs';

const encoder = new TextEncoder();

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function record(size) {
  const bytes = new Uint8Array(size);
  return {bytes, view:new DataView(bytes.buffer)};
}

function zipFixture(files, deflate = false) {
  const local = [], central = [];
  let offset = 0;
  for (const [path, content] of Object.entries(files)) {
    const name = encoder.encode(path), data = encoder.encode(content), packed = deflate ? new Uint8Array(deflateRawSync(data)) : data, crc = crc32(data);
    const first = record(30 + name.length + packed.length);
    first.view.setUint32(0, 0x04034b50, true); first.view.setUint16(4, 20, true);
    first.view.setUint16(8, deflate ? 8 : 0, true); first.view.setUint32(14, crc, true); first.view.setUint32(18, packed.length, true); first.view.setUint32(22, data.length, true);
    first.view.setUint16(26, name.length, true); first.bytes.set(name, 30); first.bytes.set(packed, 30 + name.length);
    local.push(first.bytes);
    const index = record(46 + name.length);
    index.view.setUint32(0, 0x02014b50, true); index.view.setUint16(4, 20, true); index.view.setUint16(6, 20, true);
    index.view.setUint16(10, deflate ? 8 : 0, true); index.view.setUint32(16, crc, true); index.view.setUint32(20, packed.length, true); index.view.setUint32(24, data.length, true);
    index.view.setUint16(28, name.length, true); index.view.setUint32(42, offset, true); index.bytes.set(name, 46);
    central.push(index.bytes); offset += first.bytes.length;
  }
  const centralSize = central.reduce((sum, value) => sum + value.length, 0);
  const end = record(22);
  end.view.setUint32(0, 0x06054b50, true); end.view.setUint16(8, local.length, true); end.view.setUint16(10, local.length, true);
  end.view.setUint32(12, centralSize, true); end.view.setUint32(16, offset, true);
  const result = new Uint8Array(offset + centralSize + end.bytes.length);
  let cursor = 0;
  for (const part of [...local, ...central, end.bytes]) { result.set(part, cursor); cursor += part.length; }
  return result;
}

function worksheet(classCode, roll, name) {
  const rows = [
    ['Class', 'RollNumber', 'Email', 'MemberCode', 'FullName'],
    [classCode, roll, `${roll.toLowerCase()}@example.com`, roll.toLowerCase(), name],
  ];
  const body = rows.map((values, row) => `<row r="${row + 1}">${values.map((value, column) => `<c r="${String.fromCharCode(65 + column)}${row + 1}" t="inlineStr"><is><t>${value}</t></is></c>`).join('')}</row>`).join('');
  return `<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>${body}</sheetData></worksheet>`;
}

function sharedWorkbookFile() {
  const strings = ['Class', 'RollNumber', 'Email', 'MemberCode', 'FullName', 'SE1917', 'SE000003', 'sv3@example.com', 'sv3', 'Lê Thị Chi'];
  const row = (number, indexes) => `<row r="${number}">${indexes.map((index, column) => `<c r="${String.fromCharCode(65 + column)}${number}" t="s"><v>${index}</v></c>`).join('')}</row>`;
  return zipFixture({
    'xl/workbook.xml':'<workbook xmlns:r="relationships"><sheets><sheet name="13_PRN232_SE1917" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels':'<Relationships><Relationship Id="rId1" Target="/xl/worksheets/sheet1.xml"/></Relationships>',
    'xl/sharedStrings.xml':`<sst>${strings.map(value => `<si><t>${value}</t></si>`).join('')}</sst>`,
    'xl/worksheets/sheet1.xml':`<worksheet><sheetData>${row(1, [0,1,2,3,4])}${row(2, [5,6,7,8,9])}</sheetData></worksheet>`,
  }, true);
}

function workbookFile(deflate = false) {
  const relationshipNamespace = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  return zipFixture({
    'xl/workbook.xml': `<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="${relationshipNamespace}"><sheets><sheet name="11_PRN232_SE1917" sheetId="1" r:id="rId1"/><sheet name="24_PRM393_SE1920" sheetId="2" r:id="rId2"/></sheets></workbook>`,
    'xl/_rels/workbook.xml.rels': `<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Target="worksheets/sheet2.xml"/></Relationships>`,
    'xl/worksheets/sheet1.xml': worksheet('SE1917', 'SE000001', 'Nguyễn Văn An'),
    'xl/worksheets/sheet2.xml': worksheet('SE1920', 'SE000002', 'Trần Bình'),
  }, deflate);
}

test('browser Excel importer reads every class, roster and teaching slot', async () => {
  const bytes = workbookFile();
  const result = await parseXlsx({name:'FA26_Markbook.xlsx', size:bytes.length, arrayBuffer:async () => bytes.buffer});
  assert.equal(result.book.groups.length, 2);
  assert.deepEqual(result.book.groups.map(group => [group.subjectCode, group.classCode, group.dayPair, group.slotNumber]), [
    ['PRN232', 'SE1917', 1, 1],
    ['PRM393', 'SE1920', 2, 4],
  ]);
  assert.equal(result.book.groups[0].students[0].fullName, 'Nguyễn Văn An');
  assert.equal(result.book.groups[1].students[0].memberCode, 'se000002');
  assert.ok(result.book.attendance['PRN232/SE1917'].sessions.length >= 2);
  assert.ok(result.book.attendance['PRN232/SE1917'].sessions.every(session => session.slot === 1));
  assert.ok(result.book.attendance['PRM393/SE1920'].sessions.every(session => session.slot === 4));
  const state = importMarkbook(result.book);
  assert.equal(state.groups.length, 2);
  assert.equal(state.groups[0].students[0].memberCode, 'se000001');
  assert.ok(state.sessions.length >= 4);
});

test('browser Excel importer reads normally compressed xlsx entries', async () => {
  const bytes = workbookFile(true);
  const result = await parseXlsx({name:'FA26_compressed.xlsx', size:bytes.length, arrayBuffer:async () => bytes.buffer});
  assert.equal(result.book.groups.length, 2);
  assert.equal(result.book.groups[0].students[0].rollNumber, 'SE000001');
});

test('browser Excel importer supports shared strings and absolute relationships', async () => {
  const bytes = sharedWorkbookFile();
  const result = await parseXlsx({name:'FA26_shared.xlsx', size:bytes.length, arrayBuffer:async () => bytes.buffer});
  assert.equal(result.book.groups[0].students[0].fullName, 'Lê Thị Chi');
  assert.equal(result.book.groups[0].slotNumber, 3);
});

test('browser Excel importer rejects a malformed sheet instead of silently skipping it', async () => {
  const bytes = zipFixture({
    'xl/workbook.xml':'<workbook><sheets><sheet name="BAD" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels':'<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>',
    'xl/worksheets/sheet1.xml':worksheet('SE1917', 'SE000001', 'An'),
  });
  await assert.rejects(() => parseXlsx({name:'FA26.xlsx', size:bytes.length, arrayBuffer:async () => bytes.buffer}), /Tên sheet/);
});
