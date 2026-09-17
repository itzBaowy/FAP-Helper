import {spawn} from 'node:child_process';
import {randomBytes} from 'node:crypto';
import {startServer} from './server.mjs';
const [origin,binary]=process.argv.slice(2);
if(!/^https:\/\/[a-z0-9-]+\.vercel\.app$/.test(origin||'') || !binary){
  console.error('Cần origin dạng https://ten-project.vercel.app và đường dẫn cloudflared.exe.');process.exit(1);
}
let server,child;
let stopping=false;
async function stop(){
  if(stopping)return;stopping=true;child?.kill();
  if(server)await new Promise(resolve=>server.close(resolve));
}
process.on('SIGINT',()=>stop().then(()=>process.exit(0)));
process.on('SIGTERM',()=>stop().then(()=>process.exit(0)));
try{
  const key=randomBytes(32).toString('base64url');
  server=await startServer({publicOrigin:origin,accessKey:key});
  child=spawn(binary,['tunnel','--url','http://127.0.0.1:8990','--http-host-header','127.0.0.1:8990','--no-autoupdate'],{windowsHide:true,stdio:['ignore','pipe','pipe']});
  console.log('Đang tạo kết nối HTTPS. Giữ cửa sổ này mở; Ctrl+C để dừng.');
  let buffer='',announced=false;
  const timeout=setTimeout(()=>{console.error('Chưa tạo được tunnel sau 45 giây. Kiểm tra Internet rồi thử lại.');stop();},45000);
  const output=data=>{
    buffer=(buffer+data.toString()).slice(-12000);
    const match=buffer.match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/);
    if(match&&!announced){
      announced=true;clearTimeout(timeout);
      console.log('\nMở liên kết GV này trong Chrome (không chia sẻ cho sinh viên):\n');
      console.log(`${origin}/#api=${encodeURIComponent(match[0])}&key=${key}`);
      console.log('\nMỗi lần chạy lại cần mở liên kết mới. Dữ liệu JSON vẫn được giữ trên máy.');
    }
  };
  child.stdout.on('data',output);child.stderr.on('data',output);
  child.on('error',error=>{clearTimeout(timeout);console.error(error.message);stop();process.exitCode=1;});
  child.on('exit',()=>{clearTimeout(timeout);if(!stopping){console.error('Kết nối HTTPS đã dừng. Chạy lại chương trình để kết nối.');stop();}});
}catch(error){console.error(error.code==='EADDRINUSE'?'Cổng 8990 đang dùng. Dừng cửa sổ mock-fap/start.ps1 bằng Ctrl+C rồi chạy lại.':error.message);await stop();process.exitCode=1;}
