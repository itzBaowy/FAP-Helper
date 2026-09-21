import {requestApi} from './connection.mjs';
import {parseXlsx,SLOT_TIMES} from './xlsx-importer.mjs';
const $=id=>document.getElementById(id);
let state=null,busy=false;
const dayPairs={1:'Thứ 2 + Thứ 5',2:'Thứ 3 + Thứ 6',3:'Thứ 4 + Thứ 7'};
const weekday=value=>['Chủ nhật','Thứ 2','Thứ 3','Thứ 4','Thứ 5','Thứ 6','Thứ 7'][new Date(`${value}T00:00:00Z`).getUTCDay()];
const scheduleLabel=group=>group?.dayPair&&group?.slotNumber?`${dayPairs[group.dayPair]} · Slot ${group.slotNumber}`:'Lịch từ dữ liệu đã lưu';
function message(text,error=false){$('message').textContent=text;$('message').classList.toggle('error',error);}
async function api(url,body){
  return requestApi(url,body);
}
function lock(value){busy=value;for(const id of ['import','group','session'])$(id).disabled=value;for(const select of document.querySelectorAll('select[data-mark]'))select.disabled=value;$('attendance-form').dataset.busy=String(value);$('attendance-form').querySelector('button').disabled=value;}
function updateStats(){
  const selects=[...document.querySelectorAll('select[data-mark]')];
  for(const select of selects)select.dataset.status=select.value;
  $('stat-total').textContent=selects.length;
  $('stat-present').textContent=selects.filter(s=>s.value==='P').length;
  $('stat-absent').textContent=selects.filter(s=>s.value==='A').length;
  $('stat-pending').textContent=selects.filter(s=>!s.value).length;
}
function renderGroups(){
  const old=$('group').value;
  $('group').replaceChildren();
  for(const g of state?.groups??[]) $('group').add(new Option(`${g.subject} · ${g.classCode} · ${scheduleLabel(g)}`,g.id));
  if(state?.groups.some(g=>g.id===old))$('group').value=old;
  $('workspace').hidden=!state;$('empty').hidden=!!state;
  renderSessions();
}
function renderSessions(){
  const old=$('session').value;$('session').replaceChildren();
  const sessions=(state?.sessions??[]).filter(s=>s.groupId===$('group').value);
  for(const s of sessions)$('session').add(new Option(`${s.date} · ${weekday(s.date)} · Slot ${s.slot} (${SLOT_TIMES[s.slot]})${s.isMakeup?' · Học bù':''}`,s.id));
  if(sessions.some(s=>s.id===old))$('session').value=old;
  $('session').disabled=!sessions.length;
  renderRows();
}
function renderRows(){
  const form=$('attendance-form'),session=state?.sessions.find(s=>s.id===$('session').value);
  form.hidden=!session;form.dataset.session=session?.id??'';form.dataset.revision=String(state?.revision??0);
  delete form.dataset.receipt;delete form.dataset.failed;delete form.dataset.request;
  $('students').replaceChildren();
  if(!session){if(state)message('Lớp chưa có buổi học. Hãy kiểm tra cặp ngày và slot trong tên sheet Excel.');return;}
  const group=state.groups.find(g=>g.id===session.groupId),record=state.records[session.id];
  $('title').textContent=`${group.subject} · ${group.classCode}`;$('detail').textContent=`${weekday(session.date)}, ${session.date} · Slot ${session.slot} (${SLOT_TIMES[session.slot]}) · ${scheduleLabel(group)}`;$('count').textContent=`${group.students.length} sinh viên`;
  for(const [i,s] of group.students.entries()){
    const tr=document.createElement('tr');tr.dataset.roll=s.roll;
    for(const [column,text] of [i+1,s.roll,s.name,s.memberCode,s.email].entries()){
      const td=document.createElement('td');
      if(column===2){
        const wrapper=document.createElement('div');wrapper.className='student-name';
        const avatar=document.createElement('span');avatar.className='student-avatar';avatar.dataset.color=String(i%3);avatar.setAttribute('aria-hidden','true');
        avatar.textContent=s.name.trim().split(/\s+/).slice(-2).map(word=>word[0]??'').join('').toUpperCase();
        const name=document.createElement('span');name.textContent=text;
        wrapper.append(avatar,name);td.append(wrapper);
      }else td.textContent=text;
      tr.append(td);
    }
    const td=document.createElement('td'),select=document.createElement('select');select.dataset.mark='';select.required=true;select.setAttribute('aria-label',`Điểm danh ${s.roll}`);
    for(const [value,label] of [['','Chưa ghi nhận'],['P','P · Có mặt'],['A','A · Vắng']])select.add(new Option(label,value));
    select.value=record?.marks[s.roll]??'';td.append(select);tr.append(td);$('students').append(tr);
  }
  $('saved').textContent=record?`Đã lưu lúc ${new Date(record.savedAt).toLocaleString('vi-VN')}`:'Chưa submit';
  updateStats();
}
$('students').addEventListener('change',updateStats);
$('import').addEventListener('change',async()=>{
  if(busy)return;const file=$('import').files[0];if(!file)return;lock(true);
  try{
    const isXlsx=file.name.toLowerCase().endsWith('.xlsx');
    if(!isXlsx&&file.size>10*1024*1024)throw Error('File JSON vượt quá 10 MB.');
    const parsed=isXlsx?await parseXlsx(file):{book:JSON.parse(await file.text()),warnings:[]};
    state=await api('/api/import',{book:parsed.book,revision:state?.revision??null});renderGroups();
    const warning=parsed.warnings.length?` Cảnh báo: ${parsed.warnings.map(item=>`${item.sheet?`${item.sheet}: `:''}${item.message}`).join(' ')}`:'';
    message(`Đã nhập ${state.groups.length} lớp, ${state.sessions.length} buổi và ${state.groups.reduce((sum,group)=>sum+group.students.length,0)} lượt sinh viên từ ${file.name}. Điểm danh đã submit trên trang được giữ nguyên.${warning}`);
  }
  catch(e){message(e.message,true);}finally{lock(false);$('import').value='';}
});
$('group').addEventListener('change',()=>{renderSessions();message('Đã chọn lớp. Mở extension để đối chiếu CSV.');});
$('session').addEventListener('change',()=>{renderRows();message('Đã chọn buổi. Mở extension để đối chiếu CSV.');});
$('attendance-form').addEventListener('submit',async event=>{
  event.preventDefault();if(busy)return;
  const form=event.currentTarget,sessionId=form.dataset.session,requestId=form.dataset.request||crypto.randomUUID();
  lock(true);delete form.dataset.receipt;delete form.dataset.failed;
  try{
    const marks=Object.fromEntries([...form.querySelectorAll('tr[data-roll]')].map(row=>[row.dataset.roll,row.querySelector('select').value]));
    state=await api('/api/submit',{sessionId,marks,revision:Number(form.dataset.revision)});
    form.dataset.revision=String(state.revision);form.dataset.receipt=requestId;
    $('saved').textContent=`Đã lưu lúc ${new Date(state.records[sessionId].savedAt).toLocaleString('vi-VN')}`;
    message(`Đã lưu thành công ${Object.keys(marks).length} sinh viên.`);
  }catch(e){form.dataset.failed=requestId;message(e.message,true);}finally{lock(false);}
});
try{state=await api('/api/state');renderGroups();message(state?'Dữ liệu đã tải. Chọn lớp và buổi cần điểm danh.':'Chọn file FA26.xlsx để nhập đầy đủ lớp và lịch học.');}
catch(e){message(e.message,true);lock(true);}
