import http from 'node:http';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {readFile,mkdir,open,rename,copyFile} from 'node:fs/promises';
import {importMarkbook,submitAttendance} from './model.mjs';

const root=path.dirname(fileURLToPath(import.meta.url));
export async function startServer({port=8990,directory=process.env.FAP_MOCK_DATA_DIR || path.join(process.env.APPDATA || root,'FAPHelper-Mock'),publicOrigin='',accessKey=''}={}) {
  if(publicOrigin && (!/^https:\/\/[a-z0-9-]+\.vercel\.app$/.test(publicOrigin) || !/^[A-Za-z0-9_-]{43}$/.test(accessKey))) throw Error('Origin Vercel hoặc khóa kết nối không hợp lệ.');
  const file=path.join(directory,'mock-fa26.json');
  let state=null,queue=Promise.resolve();
  try {
    state=JSON.parse(await readFile(file,'utf8'));
    if(state.schemaVersion!==1 || state.term!=='FA26' || !Array.isArray(state.groups) || !Array.isArray(state.sessions) || !state.records || !Number.isInteger(state.revision)) throw Error('File dữ liệu giả lập không hợp lệ.');
  } catch(e) { if(e.code!=='ENOENT') throw e; }
  async function save(next) {
    await mkdir(directory,{recursive:true});
    const handle=await open(file+'.tmp','w');
    try { await handle.writeFile(JSON.stringify(next,null,2)); await handle.sync(); } finally { await handle.close(); }
    try { await copyFile(file,file+'.bak'); } catch(e) { if(e.code!=='ENOENT') throw e; }
    await rename(file+'.tmp',file); state=next;
  }
  const server=http.createServer(async (req,res) => {
    res.setHeader('Cache-Control','no-store');
    res.setHeader('X-Content-Type-Options','nosniff');
    res.setHeader('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'none'");
    const reply=(status,value)=>{res.writeHead(status,{'Content-Type':'application/json; charset=utf-8'});res.end(JSON.stringify(value));};
    try {
      const expectedHosts=[`127.0.0.1:${server.address().port}`,`localhost:${server.address().port}`];
      if(!expectedHosts.includes(req.headers.host)) return reply(403,{error:'Host không được phép.'});
      const remote=publicOrigin && req.headers.origin===publicOrigin;
      if(remote){res.setHeader('Access-Control-Allow-Origin',publicOrigin);res.setHeader('Vary','Origin');}
      if(req.method==='OPTIONS' && remote && ['/api/state','/api/import','/api/submit'].includes(req.url)){
        res.writeHead(204,{'Access-Control-Allow-Methods':'GET, POST, OPTIONS','Access-Control-Allow-Headers':'Authorization, Content-Type','Access-Control-Max-Age':'600'});return res.end();
      }
      if(publicOrigin && req.url.startsWith('/api/') && (!remote || req.headers.authorization!==`Bearer ${accessKey}`)) return reply(403,{error:'Khóa kết nối không hợp lệ. Mở lại liên kết trên máy GV.'});
      if(!remote && req.headers['sec-fetch-site']==='cross-site') return reply(403,{error:'Chỉ nhận yêu cầu từ trang giả lập.'});
      if(req.method==='GET' && req.url==='/api/state') return reply(200,state);
      const assets={'/':'index.html','/app.mjs':'app.mjs','/connection.mjs':'connection.mjs','/style.css':'style.css'};
      if(req.method==='GET' && Object.hasOwn(assets,req.url)) {
        const name=assets[req.url];
        res.writeHead(200,{'Content-Type':name.endsWith('.html')?'text/html; charset=utf-8':name.endsWith('.css')?'text/css':'text/javascript'});
        return res.end(await readFile(path.join(root,'public',name)));
      }
      if(req.method!=='POST' || !['/api/import','/api/submit'].includes(req.url)) return reply(404,{error:'Không tìm thấy.'});
      if((!remote && req.headers.origin!==`http://${req.headers.host}`) || req.headers['content-type']!=='application/json') return reply(403,{error:'Nguồn yêu cầu không hợp lệ.'});
      let size=0;const chunks=[];
      for await(const chunk of req) { size+=chunk.length; if(size>10*1024*1024) return reply(413,{error:'File vượt quá 10 MB.'}); chunks.push(chunk); }
      const request=JSON.parse(Buffer.concat(chunks).toString('utf8'));
      const work=queue.then(async()=> {
        if(req.url==='/api/import' && (request.revision ?? null)!==(state?.revision ?? null)) throw Error('Dữ liệu đã đổi. Tải lại trang trước khi import.');
        const next=req.url==='/api/import'?importMarkbook(request.book,state):submitAttendance(state,request);
        if(next!==state) await save(next);
        return state;
      });
      queue=work.catch(()=>{});
      return reply(200,await work);
    } catch(e) { reply(400,{error:e.code?'Không ghi/đọc được file dữ liệu giả lập. Kiểm tra quyền truy cập và dung lượng.':e.message}); }
  });
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,'127.0.0.1',resolve);});
  return server;
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  startServer().then(server=>console.log(`FAP Mock: http://127.0.0.1:${server.address().port} — Ctrl+C để dừng.`)).catch(e=>{console.error(e.message);process.exitCode=1;});
}
