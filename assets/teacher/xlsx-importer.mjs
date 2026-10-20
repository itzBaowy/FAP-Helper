const MAX_FILE_BYTES = 25 * 1024 * 1024;
const MAX_UNCOMPRESSED_BYTES = 64 * 1024 * 1024;
const MAX_ENTRIES = 5000;
const HEADERS = ['Class', 'RollNumber', 'Email', 'MemberCode', 'FullName'];
const SHEET_PATTERN = /^([1-3])([1-4])_([A-Z][A-Z0-9]*)_([A-Z][A-Z0-9]*)$/;
const TERM_START = '2026-09-07';
const SLOT_TIMES = {
  1: '07:30–09:15',
  2: '09:30–11:45',
  3: '12:30–14:45',
  4: '15:00–17:15',
};

const decoder = new TextDecoder();
const little = (view, offset, bytes) => bytes === 2
  ? view.getUint16(offset, true)
  : view.getUint32(offset, true);

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function xmlText(value) {
  return value
    .replace(/<[^>]*>/g, '')
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'").replace(/&amp;/g, '&')
    .replace(/&#x([0-9a-f]+);/gi, (_, code) => String.fromCodePoint(Number.parseInt(code, 16)))
    .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(Number(code)))
    .replace(/_x([0-9a-f]{4})_/gi, (_, code) => String.fromCharCode(Number.parseInt(code, 16)));
}

function attributes(source) {
  return Object.fromEntries([...source.matchAll(/([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)]
    .map(match => [match[1], xmlText(match[2] ?? match[3] ?? '')]));
}

function blocks(xml, tag) {
  const expression = new RegExp(`<(?:\\w+:)?${tag}\\b([^>]*)>([\\s\\S]*?)<\\/(?:\\w+:)?${tag}>`, 'gi');
  return [...xml.matchAll(expression)].map(match => ({attrs: attributes(match[1]), body: match[2]}));
}

function elements(xml, tag) {
  const expression = new RegExp(`<(?:\\w+:)?${tag}\\b([^>]*?)(?:\\/?>)`, 'gi');
  return [...xml.matchAll(expression)].map(match => attributes(match[1]));
}

function findEndRecord(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const first = Math.max(0, bytes.length - 65557);
  for (let offset = bytes.length - 22; offset >= first; offset--) {
    if (little(view, offset, 4) === 0x06054b50 && offset + 22 + little(view, offset + 20, 2) === bytes.length) return offset;
  }
  throw Error('File không phải workbook .xlsx hợp lệ.');
}

function zipDirectory(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const end = findEndRecord(bytes);
  const count = little(view, end + 10, 2);
  const directoryOffset = little(view, end + 16, 4);
  if (count > MAX_ENTRIES) throw Error('Workbook có quá nhiều thành phần để xử lý.');
  const entries = new Map();
  let offset = directoryOffset;
  let total = 0;
  for (let index = 0; index < count; index++) {
    if (offset + 46 > bytes.length || little(view, offset, 4) !== 0x02014b50) throw Error('Thư mục ZIP trong file Excel không hợp lệ.');
    const flags = little(view, offset + 8, 2);
    const method = little(view, offset + 10, 2);
    const crc = little(view, offset + 16, 4);
    const compressedSize = little(view, offset + 20, 4);
    const size = little(view, offset + 24, 4);
    const nameLength = little(view, offset + 28, 2);
    const extraLength = little(view, offset + 30, 2);
    const commentLength = little(view, offset + 32, 2);
    const localOffset = little(view, offset + 42, 4);
    const name = decoder.decode(bytes.subarray(offset + 46, offset + 46 + nameLength)).replaceAll('\\', '/').replace(/^\/+/, '');
    if ((flags & 1) !== 0 || ![0, 8].includes(method) || name.includes('../')) throw Error('Workbook chứa thành phần ZIP không được hỗ trợ.');
    total += size;
    if (total > MAX_UNCOMPRESSED_BYTES) throw Error('Nội dung Excel vượt quá giới hạn xử lý 64 MB.');
    if (entries.has(name)) throw Error('Workbook chứa thành phần ZIP bị trùng.');
    entries.set(name, {method, crc, compressedSize, size, localOffset});
    offset += 46 + nameLength + extraLength + commentLength;
  }
  return {entries, view};
}

async function unzip(bytes) {
  const {entries, view} = zipDirectory(bytes);
  const cache = new Map();
  async function read(name) {
    name = name.replace(/^\/+/, '');
    if (cache.has(name)) return cache.get(name);
    const entry = entries.get(name);
    if (!entry) throw Error(`File Excel thiếu thành phần ${name}.`);
    const offset = entry.localOffset;
    if (offset + 30 > bytes.length || little(view, offset, 4) !== 0x04034b50) throw Error('Dữ liệu ZIP trong file Excel không hợp lệ.');
    const nameLength = little(view, offset + 26, 2);
    const extraLength = little(view, offset + 28, 2);
    const start = offset + 30 + nameLength + extraLength;
    const compressed = bytes.slice(start, start + entry.compressedSize);
    let output;
    if (entry.method === 0) output = compressed;
    else {
      if (typeof DecompressionStream !== 'function') throw Error('Trình duyệt này chưa hỗ trợ giải nén .xlsx. Hãy dùng Chrome hoặc Edge phiên bản mới.');
      try {
        output = new Uint8Array(await new Response(new Blob([compressed]).stream().pipeThrough(new DecompressionStream('deflate-raw'))).arrayBuffer());
      } catch (_) {
        throw Error('Không giải nén được nội dung file Excel.');
      }
    }
    if (output.length !== entry.size || crc32(output) !== entry.crc) throw Error('Nội dung file Excel bị lỗi hoặc không đầy đủ.');
    cache.set(name, output);
    return output;
  }
  return {entries, text: async name => decoder.decode(await read(name))};
}

function resolvePart(base, target) {
  const url = new URL(target.replaceAll('\\', '/'), `https://xlsx.local/${base}`);
  const path = decodeURIComponent(url.pathname).replace(/^\/+/, '');
  if (!path.startsWith('xl/')) throw Error('Đường dẫn thành phần Excel không hợp lệ.');
  return path;
}

function cellValue(cell, sharedStrings) {
  if (cell.attrs.t === 'inlineStr') return blocks(cell.body, 't').map(value => xmlText(value.body)).join('').trim();
  const raw = blocks(cell.body, 'v')[0]?.body ?? '';
  if (cell.attrs.t === 's') {
    const index = Number(raw);
    if (!Number.isInteger(index) || index < 0 || index >= sharedStrings.length) throw Error('Bảng chuỗi Excel không hợp lệ.');
    return sharedStrings[index].trim();
  }
  return xmlText(raw).trim();
}

function vietnamDate() {
  const parts = new Intl.DateTimeFormat('en-CA', {timeZone: 'Asia/Bangkok', year: 'numeric', month: '2-digit', day: '2-digit'}).formatToParts();
  const value = Object.fromEntries(parts.map(part => [part.type, part.value]));
  return `${value.year}-${value.month}-${value.day}`;
}

function addDays(value, days) {
  const date = new Date(`${value}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function plannedSessions(dayPair, slot) {
  const today = vietnamDate();
  const through = addDays(today < TERM_START ? TERM_START : today, 14);
  const sessions = [];
  for (let date = TERM_START; date <= through && sessions.length < 200; date = addDays(date, 1)) {
    const weekday = new Date(`${date}T00:00:00Z`).getUTCDay() || 7;
    if (weekday === dayPair || weekday === dayPair + 3) {
      sessions.push({date, slot, isMakeup:false, state:'planned', marks:{}, openedAt:null, closedAt:null, note:''});
    }
  }
  return sessions;
}

export async function parseXlsx(file) {
  if (!file?.name?.toLowerCase().endsWith('.xlsx')) throw Error('Vui lòng chọn file Excel .xlsx.');
  if (file.size > MAX_FILE_BYTES) throw Error('File vượt quá giới hạn 25 MB.');
  let archive;
  try {
    archive = await unzip(new Uint8Array(await file.arrayBuffer()));
  } catch (error) {
    if (error?.message) throw error;
    throw Error('Không đọc được cấu trúc Excel. Hãy lưu lại file dưới định dạng .xlsx và thử lại.');
  }
  const workbook = await archive.text('xl/workbook.xml');
  const relations = new Map();
  for (const relation of elements(await archive.text('xl/_rels/workbook.xml.rels'), 'Relationship')) {
    if (relation.TargetMode !== 'External' && relation.Id && relation.Target) relations.set(relation.Id, resolvePart('xl/workbook.xml', relation.Target));
  }
  const sharedStrings = [];
  if (archive.entries.has('xl/sharedStrings.xml')) {
    for (const item of blocks(await archive.text('xl/sharedStrings.xml'), 'si')) sharedStrings.push(blocks(item.body, 't').map(value => xmlText(value.body)).join(''));
  }
  const issues = [];
  const groups = [];
  const ids = new Set();
  const identityEmails = new Map();
  const emailOwners = new Map();
  const fileTerm = file.name.toUpperCase().match(/(?:^|[^A-Z0-9])((?:FA|SP|SU)\d{2})(?:[^A-Z0-9]|$)/)?.[1];
  if (fileTerm && fileTerm !== 'FA26') issues.push({message:`File mang mã kỳ ${fileTerm}. Phiên bản này chỉ quản lý FA26.`, error:true});
  else if (!fileTerm) issues.push({message:'Tên file không có mã học kỳ. Dữ liệu sẽ được nhập vào FA26.', error:false});

  for (const sheet of elements(workbook, 'sheet')) {
    const name = sheet.name ?? '';
    const match = name.toUpperCase().match(SHEET_PATTERN);
    if (!match) {
      issues.push({message:'Tên sheet phải có dạng 11_PRN232_SE1917; cặp ngày 1–3, slot 1–4.', sheet:name, error:true});
      continue;
    }
    const [, pairText, slotText, subjectCode, classCode] = match;
    const id = `${subjectCode}/${classCode}`;
    if (ids.has(id)) {
      issues.push({message:`Trùng lớp học phần ${subjectCode} – ${classCode} ở nhiều sheet.`, sheet:name, error:true});
      continue;
    }
    ids.add(id);
    const relationId = Object.entries(sheet).find(([key]) => key === 'r:id' || key.endsWith(':id'))?.[1];
    const target = relations.get(relationId);
    if (!target) throw Error(`Không tìm thấy dữ liệu sheet ${name}.`);
    const rows = blocks(await archive.text(target), 'row');
    const columnMap = new Map();
    const students = [];
    const rolls = new Set();
    const emails = new Set();
    let foundHeader = false;
    for (const row of rows) {
      const rowNumber = Number(row.attrs.r) || undefined;
      const cells = new Map();
      for (const cell of blocks(row.body, 'c')) {
        const column = (cell.attrs.r ?? '').replace(/\d/g, '').toUpperCase();
        if (column) cells.set(column, cell);
      }
      const values = new Map([...cells].map(([column, cell]) => [column, cellValue(cell, sharedStrings)]));
      if ([...values.values()].every(value => !value)) continue;
      if (!foundHeader) {
        foundHeader = true;
        for (const header of HEADERS) {
          const matches = [...values].filter(([, value]) => value.toLowerCase() === header.toLowerCase());
          if (matches.length !== 1) issues.push({message:`Cột ${header} bị thiếu hoặc xuất hiện nhiều lần.`, sheet:name, row:rowNumber, error:true});
          else columnMap.set(header, matches[0][0]);
        }
        if (columnMap.size !== HEADERS.length) break;
        continue;
      }
      const fields = Object.fromEntries(HEADERS.map(header => [header, values.get(columnMap.get(header)) ?? '']));
      const missing = Object.entries(fields).filter(([, value]) => !value).map(([key]) => key);
      if (missing.length) {
        issues.push({message:`Thiếu ${missing.join(', ')}.`, sheet:name, row:rowNumber, error:true});
        continue;
      }
      if ([...columnMap.values()].some(column => cells.get(column)?.body.match(/<(?:\w+:)?f\b/i))) {
        issues.push({message:'Thông tin sinh viên phải là giá trị, không dùng công thức Excel.', sheet:name, row:rowNumber, error:true});
        continue;
      }
      const roll = fields.RollNumber.toUpperCase();
      const email = fields.Email.toLowerCase();
      const errors = [];
      if (fields.Class.toUpperCase() !== classCode) errors.push(`Class không khớp lớp ${classCode} trong tên sheet.`);
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) errors.push('Email không hợp lệ.');
      if (rolls.has(roll)) errors.push('MSSV bị trùng trong sheet.');
      if (emails.has(email)) errors.push('Email bị trùng trong sheet.');
      if (identityEmails.has(roll) && identityEmails.get(roll) !== email) errors.push('Một MSSV có email khác nhau giữa các sheet.');
      if (emailOwners.has(email) && emailOwners.get(email) !== roll) errors.push('Một email được dùng cho nhiều MSSV.');
      rolls.add(roll); emails.add(email);
      for (const message of errors) issues.push({message, sheet:name, row:rowNumber, error:true});
      if (errors.length) continue;
      identityEmails.set(roll, email); emailOwners.set(email, roll);
      students.push({classCode, rollNumber:roll, email, memberCode:fields.MemberCode, fullName:fields.FullName});
    }
    if (!foundHeader || !students.length) issues.push({message:'Sheet không có danh sách sinh viên hợp lệ.', sheet:name, error:true});
    groups.push({sheetName:name, subjectCode, classCode, dayPair:Number(pairText), slotNumber:Number(slotText), students});
  }
  if (!groups.length) issues.push({message:'Không tìm thấy lớp học phần để import.', error:true});
  const occupied = new Map();
  for (const group of groups) {
    const schedule = `${group.dayPair}/${group.slotNumber}`;
    if (occupied.has(schedule)) issues.push({message:`Trùng giờ với ${occupied.get(schedule)}. Kiểm tra lại lịch dạy.`, sheet:group.sheetName, error:false});
    else occupied.set(schedule, `${group.subjectCode} – ${group.classCode}`);
  }
  const errors = issues.filter(issue => issue.error);
  if (errors.length) {
    const details = errors.slice(0, 4).map(issue => `${issue.sheet ? `${issue.sheet}${issue.row ? ` · dòng ${issue.row}` : ''}: ` : ''}${issue.message}`);
    throw Error(`${details.join(' ')}${errors.length > 4 ? ` (+${errors.length - 4} lỗi khác)` : ''}`);
  }
  groups.sort((a, b) => a.sheetName.localeCompare(b.sheetName));
  const attendance = Object.fromEntries(groups.map(group => [
    `${group.subjectCode}/${group.classCode}`,
    {plannedTotal:null, sessions:plannedSessions(group.dayPair, group.slotNumber), history:[]},
  ]));
  return {
    book:{schemaVersion:2, termCode:'FA26', termStart:TERM_START, termEnd:null, totalSessions:null, sourceName:file.name, importedAt:new Date().toISOString(), groups, attendance},
    warnings:issues.filter(issue => !issue.error),
    slotTimes:SLOT_TIMES,
  };
}

export {HEADERS, SLOT_TIMES};
