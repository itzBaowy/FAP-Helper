import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm,mkdir,writeFile} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {parseCsv,headers} from '../extension/csv.mjs';
import {importMarkbook,submitAttendance} from '../mock-fap/model.mjs';
import {startServer} from '../mock-fap/server.mjs';
const csv=await readFile(new URL('../mock-fap/demo/FA26-demo.csv',import.meta.url),'utf8');
const book=JSON.parse(await readFile(new URL('../mock-fap/demo/FA26-demo.json',import.meta.url),'utf8'));
const sessions=parseCsv(csv);
const request=state=>({revision:state.revision,sessionId:sessions[0].id,marks:Object.fromEntries(sessions[0].students.map(s=>[s.roll,s.status]))});
test('real Dart export: BOM, two sessions, P/A and Vietnamese',()=>{
  assert.equal(sessions.length,2);assert.equal(sessions[0].students.length,3);assert.equal(sessions[0].students[0].status,'P');assert.match(sessions[0].students[0].name,/Nguyễn/);
  assert.equal(parseCsv(csv.replace('Nguyễn Văn An','Nguyễn, ""An""\r\nA'))[0].students[0].name,'Nguyễn, "An"\r\nA');
});
test('invalid CSV is rejected as a whole',()=>{
  for(const text of [csv.replace('"P"','"X"'),csv.replace('"FA26"','"FA25"'),csv.replace('"2026-09-07"','"2026-02-31"'),csv.replace('"07:30"','"07:00"'),csv.replace('"SE000002"','"SE000001"'),csv+'"unterminated',csv.replace('"SchemaVersion"','"Wrong"'),csv.replace('"P",','"P"x,'),csv.replace('"2026-09-07"','"2026-09-08"')])assert.throws(()=>parseCsv(text));
  assert.throws(()=>parseCsv('x'.repeat(5*1024*1024+1)));
  assert.equal(headers.length,17);
});
test('mock imports roster and calendar without copying desktop P/A; preserves submitted data',()=>{
  const state=importMarkbook(book);assert.deepEqual(state.records,{});assert.equal(state.sessions.length,2);
  const saved=submitAttendance(state,request(state));assert.equal(saved.records[sessions[0].id].marks.SE000002,'A');
  assert.deepEqual(importMarkbook(book,saved).records,saved.records);
  assert.equal(submitAttendance(saved,request(saved)),saved);
  const changed=structuredClone(book);changed.groups[0].students.pop();assert.throws(()=>importMarkbook(changed,saved));
  const missing=structuredClone(book);missing.attendance[book.groups[0].subjectCode+'/'+book.groups[0].classCode].sessions=[];assert.throws(()=>importMarkbook(missing,saved));
});
test('stale revision, unknown session, missing/extra/invalid marks rejected',()=>{
  const state=importMarkbook(book),r=request(state);
  for(const bad of [{...r,revision:0},{...r,sessionId:'wrong'},{...r,marks:{SE000001:'P'}},{...r,marks:{...r.marks,SE999999:'A'}},{...r,marks:{...r.marks,SE000001:'X'}}])assert.throws(()=>submitAttendance(state,bad));
  assert.deepEqual(state.records,{});
});
test('remote API requires exact allowed origin and secret, including roster reads',async()=>{
  const directory=await mkdtemp(path.join(os.tmpdir(),'fap-remote-test-'));
  const publicOrigin='https://fap-mock-test.vercel.app',accessKey='a'.repeat(43);
  const server=await startServer({port:0,directory,publicOrigin,accessKey});
  const origin=`http://127.0.0.1:${server.address().port}`;
  try{
    for(const headers of [{},{Origin:publicOrigin},{Origin:publicOrigin,Authorization:'Bearer wrong'},{Origin:'https://wrong.vercel.app',Authorization:`Bearer ${accessKey}`}]){
      assert.equal((await fetch(origin+'/api/state',{headers})).status,403);
    }
    const headers={Origin:publicOrigin,Authorization:`Bearer ${accessKey}`};
    const response=await fetch(origin+'/api/state',{headers});
    assert.equal(response.status,200);assert.equal(response.headers.get('access-control-allow-origin'),publicOrigin);
    const preflight=await fetch(origin+'/api/import',{method:'OPTIONS',headers:{Origin:publicOrigin,'Access-Control-Request-Method':'POST','Access-Control-Request-Headers':'authorization,content-type'}});
    assert.equal(preflight.status,204);
    const imported=await fetch(origin+'/api/import',{method:'POST',headers:{...headers,'Content-Type':'application/json'},body:JSON.stringify({book})});
    assert.equal(imported.status,200);
  }finally{await new Promise(r=>server.close(r));await rm(directory,{recursive:true,force:true});}
});
test('HTTP persists across restart, protects origin, fails safely on disk error',async()=>{
  const directory=await mkdtemp(path.join(os.tmpdir(),'fap-phase4-'));let server;
  try{
    server=await startServer({port:0,directory});let origin=`http://127.0.0.1:${server.address().port}`;
    assert.equal((await fetch(origin+'/xlsx-importer.mjs')).status,200);
    const post=(url,body,source=origin)=>fetch(origin+url,{method:'POST',headers:{'Content-Type':'application/json',Origin:source},body:JSON.stringify(body)});
    assert.equal((await post('/api/import',{book},'https://evil.example')).status,403);
    let response=await post('/api/import',{book});assert.equal(response.status,200);let state=await response.json();
    response=await post('/api/submit',request(state));assert.equal(response.status,200);state=await response.json();
    assert.equal((await post('/api/submit',request({...state,revision:state.revision-1}))).status,400);
    await new Promise(r=>server.close(r));server=await startServer({port:0,directory});origin=`http://127.0.0.1:${server.address().port}`;
    assert.deepEqual((await (await fetch(origin+'/api/state')).json()).records,state.records);
    await mkdir(path.join(directory,'mock-fa26.json.tmp'));
    const bad=request(state);bad.marks.SE000001='A';assert.equal((await post('/api/submit',bad)).status,400);
    assert.deepEqual((await (await fetch(origin+'/api/state')).json()).records,state.records);
    await writeFile(path.join(directory,'unrelated.txt'),'keep');
  }finally{if(server)await new Promise(r=>server.close(r));await rm(directory,{recursive:true,force:true});}
});
