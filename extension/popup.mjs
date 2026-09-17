import {parseCsv} from './csv.mjs';
import {interactWithMock} from './adapter.mjs';
const $ = id => document.getElementById(id);
let sessions = [], checked = null, busy = false;
function message(text,error=false) { $('message').textContent=text; $('message').classList.toggle('error',error); }
function step(index) {
  ['step-file','step-check','step-save'].forEach((id,i)=>$(id).classList.toggle('active',i<=index));
}
function invalidate() { checked=null; $('submit').disabled=true; $('summary').hidden=true; step(sessions.length?1:0); }
function lock(value) { busy=value; $('file').disabled=value; $('session').disabled=value||!sessions.length; $('preview').disabled=value||!sessions.length; $('submit').disabled=value||!checked; }
$('file').addEventListener('change',async () => {
  sessions=[]; invalidate(); $('session').replaceChildren(); lock(true);
  $('file-name').textContent='Chọn file từ máy tính';
  $('file-hint').textContent='CSV đã xuất từ FAP Helper · tối đa 5 MB';
  try {
    const file=$('file').files[0];
    if (!file) { message('Chưa chọn CSV.'); return; }
    if (file.size>5*1024*1024) throw Error('CSV vượt quá 5 MB.');
    sessions=parseCsv(await file.text());
    $('file-name').textContent=file.name;
    $('file-name').title=file.name;
    $('file-hint').textContent=`${sessions.length} buổi học · Sẵn sàng đối chiếu`;
    step(1);
    for (const s of sessions) $('session').add(new Option(`${s.subject} · ${s.classCode} · ${s.date} · Slot ${s.slot}`,s.id));
    message(`Đã đọc ${sessions.length} buổi. Chọn buổi và đối chiếu với trang.`);
  } catch(e) { message(e.message,true); } finally { lock(false); }
});
$('session').addEventListener('change',() => { invalidate(); message('Buổi đã thay đổi. Hãy đối chiếu lại.'); });
async function run(submit) {
  if(busy) return;
  lock(true);
  try {
    const session=sessions.find(s=>s.id===$('session').value);
    if(!session) throw Error('Chưa chọn buổi.');
    const [tab]=await chrome.tabs.query({active:true,currentWindow:true});
    if(!tab?.id) throw Error('Không tìm thấy tab hiện tại.');
    if(submit && (!checked || checked.tabId!==tab.id || checked.sessionId!==session.id)) throw Error('Tab hoặc buổi đã thay đổi. Hãy đối chiếu lại.');
    const {mockOrigin=''}=await chrome.storage.local.get('mockOrigin');
    const [injected]=await chrome.scripting.executeScript({target:{tabId:tab.id},func:interactWithMock,args:[session,submit,submit?checked.revision:null,mockOrigin]});
    const result=injected?.result;
    if(!result?.ok) throw Error(result?.error||'Không đọc được trang giả lập.');
    if(submit) { invalidate(); step(2); message(`Đã lưu thành công ${result.count} sinh viên trên trang giả lập.`); }
    else {
      checked={tabId:tab.id,sessionId:session.id,revision:result.revision};
      $('summary-count').textContent=`${result.count} sinh viên`;
      $('summary-session').textContent=`${session.subject} · ${session.classCode} / ${session.date} · Slot ${session.slot}`;
      $('summary-present').textContent=result.present;
      $('summary-absent').textContent=result.absent;
      $('summary-changed').textContent=result.changed;
      $('summary').hidden=false; message('Đối chiếu thành công. Có thể điền và submit.');
      step(2);
      $('summary').scrollIntoView({block:'nearest'});
    }
  } catch(e) { invalidate(); message(e.message,true); } finally { lock(false); }
}
$('preview').addEventListener('click',()=>run(false));
$('submit').addEventListener('click',()=>run(true));
chrome.storage.local.get('mockOrigin').then(({mockOrigin=''})=>{$('mock-origin').value=mockOrigin;}).catch(()=>message('Không đọc được cấu hình extension.',true));
$('save-origin').addEventListener('click',async()=>{
  if(busy)return;
  const origin=$('mock-origin').value.trim().replace(/\/$/,'');
  if(origin && !/^https:\/\/[a-z0-9-]+\.vercel\.app$/.test(origin)){message('Nhập domain dạng https://ten-project.vercel.app, không kèm đường dẫn hoặc khóa kết nối.',true);return;}
  try{await chrome.storage.local.set({mockOrigin:origin});invalidate();message('Đã lưu địa chỉ trang giả lập. Hãy đối chiếu lại CSV.');}
  catch{message('Không lưu được cấu hình extension.',true);}
});
