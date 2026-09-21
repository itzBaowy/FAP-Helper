const code = value => typeof value === 'string' && /^[A-Z0-9]+$/.test(value);
const text = value => typeof value === 'string' && value.trim().length > 0 && value.length <= 500;
export function importMarkbook(book, previous = null) {
  if (book?.schemaVersion !== 2 || book.termCode !== 'FA26' || !Array.isArray(book.groups) || !book.groups.length || book.groups.length > 200) throw Error('Dữ liệu phải đúng cấu trúc học kỳ FA26.');
  const groups = [], sessions = [], ids = new Set();
  for (const g of book.groups) {
    if (!code(g.subjectCode) || !code(g.classCode) || !Number.isInteger(g.dayPair) || g.dayPair < 1 || g.dayPair > 3 || !Number.isInteger(g.slotNumber) || g.slotNumber < 1 || g.slotNumber > 4 || !Array.isArray(g.students) || !g.students.length || g.students.length > 1000) throw Error('Danh sách lớp hoặc lịch học không hợp lệ.');
    const id = `${g.subjectCode}/${g.classCode}`;
    if (ids.has(id)) throw Error('Trùng lớp học phần.'); ids.add(id);
    const rolls = new Set();
    const students = g.students.map(s => {
      if (!code(s.rollNumber) || s.classCode !== g.classCode || rolls.has(s.rollNumber) || !text(s.fullName) || !text(s.email) || !text(s.memberCode)) throw Error('MSSV, tên, email hoặc MemberCode không hợp lệ.');
      rolls.add(s.rollNumber); return {roll:s.rollNumber, name:s.fullName, email:s.email, memberCode:s.memberCode};
    });
    groups.push({id, subject:g.subjectCode, classCode:g.classCode, sheetName:g.sheetName ?? '', dayPair:g.dayPair, slotNumber:g.slotNumber, students});
    const stored = book.attendance?.[id]?.sessions ?? [];
    if (!Array.isArray(stored) || stored.length > 400) throw Error('Danh sách buổi học không hợp lệ.');
    const unique = new Set();
    for (const s of stored) {
      const date = new Date(s.date + 'T00:00:00Z');
      if (!/^\d{4}-\d{2}-\d{2}$/.test(s.date) || !Number.isFinite(date.getTime()) || date.toISOString().slice(0,10) !== s.date || s.date < '2026-09-07' || !Number.isInteger(s.slot) || s.slot < 1 || s.slot > 4 || !['planned','open','closed','cancelled'].includes(s.state)) throw Error('Ngày, slot hoặc trạng thái buổi không hợp lệ.');
      const sessionId = `FA26/${id}/${s.date}/${s.slot}`;
      if(unique.has(sessionId)) throw Error('Trùng buổi học.'); unique.add(sessionId);
      if(s.state !== 'cancelled') sessions.push({id:sessionId, groupId:id, date:s.date, slot:s.slot, state:s.state, isMakeup:s.isMakeup===true});
    }
  }
  // Re-import preserves submitted sessions only when their roster is unchanged.
  const records = {};
  for (const [id, record] of Object.entries(previous?.records ?? {})) {
    const s=sessions.find(s=>s.id===id), g=groups.find(g=>g.id===s?.groupId);
    if(!g || Object.keys(record.marks).length!==g.students.length || g.students.some(s=>!Object.hasOwn(record.marks,s.roll))) throw Error('Import sẽ làm mất buổi đã submit hoặc thay đổi danh sách lớp đã submit. Giữ file cũ để đối chiếu.');
    records[id]=record;
  }
  return {schemaVersion:1, term:'FA26', groups, sessions:sessions.sort((a,b)=>a.id.localeCompare(b.id)), records, revision:(previous?.revision??0)+1};
}

export function submitAttendance(state, request) {
  if (!state || request?.revision !== state.revision) throw Error('Dữ liệu đã thay đổi. Tải lại trang và đối chiếu lại.');
  const session=state.sessions.find(s=>s.id===request.sessionId);
  const group=state.groups.find(g=>g.id===session?.groupId);
  if(!group || !request.marks || Array.isArray(request.marks) || Object.keys(request.marks).length!==group.students.length || group.students.some(s=>!Object.hasOwn(request.marks,s.roll)||!['P','A'].includes(request.marks[s.roll]))) throw Error('Buổi học hoặc danh sách P/A không khớp.');
  const old=state.records[session.id];
  if(old && group.students.every(s=>old.marks[s.roll]===request.marks[s.roll])) return state;
  const record={marks:Object.fromEntries(group.students.map(s=>[s.roll,request.marks[s.roll]])), savedAt:new Date().toISOString()};
  return {...state,revision:state.revision+1,records:{...state.records,[session.id]:record}};
}
