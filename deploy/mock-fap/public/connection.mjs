const local=['http://127.0.0.1:8990','http://localhost:8990'].includes(location.origin);
let connection;
const storageKey='fap-mock-connection';
export function getConnection(){
  if(local)return null;
  if(connection)return connection;
  const fragment=new URLSearchParams(location.hash.slice(1));
  const fresh=fragment.has('api')||fragment.has('key');
  if(fresh)history.replaceState(null,'',location.pathname);
  let candidate;
  try{
    candidate=fresh?{api:fragment.get('api'),key:fragment.get('key')}:JSON.parse(sessionStorage.getItem(storageKey)||'null');
    if(!candidate || !/^https:\/\/[a-z0-9-]+\.trycloudflare\.com$/.test(candidate.api) || !/^[A-Za-z0-9_-]{43}$/.test(candidate.key))throw Error();
  }catch{
    sessionStorage.removeItem(storageKey);
    throw Error('Chưa kết nối máy GV. Chạy start-vercel.ps1 trên máy GV và mở liên kết chương trình cung cấp.');
  }
  connection=candidate;
  sessionStorage.setItem(storageKey,JSON.stringify(candidate));
  return connection;
}
export async function requestApi(url,body){
  const link=getConnection();
  const headers=body===undefined?{}:{'Content-Type':'application/json'};
  if(link)headers.Authorization=`Bearer ${link.key}`;
  const response=await fetch((link?.api??'')+url,{method:body===undefined?'GET':'POST',headers,body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000),credentials:'omit',referrerPolicy:'no-referrer'});
  const result=await response.json();if(!response.ok)throw Error(result.error||'Không thể lưu.');return result;
}
