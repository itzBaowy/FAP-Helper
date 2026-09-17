export const headers = 'SchemaVersion,Term,SubjectCode,ClassCode,SessionId,SessionNumber,Date,Slot,StartTime,EndTime,RollNumber,Email,FullName,MemberCode,Status,ClosedAt,ExportedAt'.split(',');

// Strict CSV state machine: embedded newlines and doubled quotes are data.
export function parseCsv(text) {
  if (text.length > 5 * 1024 * 1024) throw Error('CSV vượt quá 5 MB.');
  text = text.replace(/^\uFEFF/, '');
  const rows = []; let row = [], cell = '', state = 'start';
  const field = () => { row.push(cell); cell = ''; state = 'start'; };
  const line = () => { field(); rows.push(row); row = []; };
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (state === 'quoted') {
      if (c === '"') {
        if (text[i + 1] === '"') { cell += '"'; i++; }
        else state = 'closed';
      } else cell += c;
    } else if (c === ',') field();
    else if (c === '\r' || c === '\n') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      line();
    } else if (c === '"' && state === 'start') state = 'quoted';
    else {
      if (state === 'closed' || c === '"') throw Error('CSV có dấu nháy không hợp lệ.');
      cell += c; state = 'plain';
    }
  }
  if (state === 'quoted') throw Error('CSV thiếu dấu nháy đóng.');
  if (state !== 'start' || row.length || cell) line();
  if (rows.length < 2 || rows[0].length !== headers.length || rows[0].some((cell, i) => cell !== headers[i])) throw Error('CSV không đúng định dạng xuất từ FAP Helper.');
  const sessions = new Map();
  for (let i = 1; i < rows.length; i++) {
    if (rows[i].length !== headers.length) throw Error(`Dòng ${i + 1}: sai số cột.`);
    const r = Object.fromEntries(headers.map((key, j) => [key, rows[i][j]]));
    const fail = () => { throw Error(`Dòng ${i + 1}: thông tin buổi học hoặc điểm danh không hợp lệ.`); };
    if (r.SchemaVersion !== '1' || r.Term !== 'FA26' || !/^[A-Z0-9]+$/.test(r.SubjectCode) ||
        !/^[A-Z0-9]+$/.test(r.ClassCode) || !/^[A-Z0-9]+$/.test(r.RollNumber) ||
        !/^[1-4]$/.test(r.Slot) || !/^[1-9]\d*$/.test(r.SessionNumber) ||
        !/^\d{4}-\d{2}-\d{2}$/.test(r.Date) || !['P','A'].includes(r.Status)) fail();
    const date = new Date(r.Date + 'T00:00:00Z');
    if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0,10) !== r.Date || r.Date < '2026-09-07') fail();
    if (r.SessionId !== `${r.Term}/${r.SubjectCode}/${r.ClassCode}/${r.Date}/${r.Slot}`) fail();
    const times = [['07:30','09:15'],['09:30','11:45'],['12:30','14:45'],['15:00','17:15']][Number(r.Slot)-1];
    if (r.StartTime !== times[0] || r.EndTime !== times[1]) fail();
    if (!Number.isFinite(Date.parse(r.ClosedAt)) || !Number.isFinite(Date.parse(r.ExportedAt))) fail();
    if (!sessions.has(r.SessionId)) sessions.set(r.SessionId, {id:r.SessionId, term:r.Term, subject:r.SubjectCode, classCode:r.ClassCode, date:r.Date, slot:r.Slot, number:r.SessionNumber, closedAt:r.ClosedAt, exportedAt:r.ExportedAt, students:[]});
    const session = sessions.get(r.SessionId);
    if (session.number !== r.SessionNumber || session.closedAt !== r.ClosedAt || session.exportedAt !== r.ExportedAt) fail();
    if (session.students.some(s => s.roll === r.RollNumber)) throw Error(`Dòng ${i + 1}: MSSV bị trùng trong buổi học.`);
    session.students.push({roll:r.RollNumber, name:r.FullName, status:r.Status});
  }
  return [...sessions.values()];
}
