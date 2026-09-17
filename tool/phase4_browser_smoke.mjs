import {createRequire} from 'node:module';
import {readFile,mkdtemp,rm,mkdir,writeFile} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {startServer} from '../mock-fap/server.mjs';
import {parseCsv} from '../extension/csv.mjs';
import {interactWithMock} from '../extension/adapter.mjs';
const require=createRequire(import.meta.url);
const {chromium}=require('../build/browser-tools/node_modules/playwright');
const directory=await mkdtemp(path.join(os.tmpdir(),'fap-mock-browser-'));
let server,context;
const checks=[];
const remote=process.argv.includes('--vercel');
const publicOrigin=remote?'https://fap-mock-test.vercel.app':'';
const accessKey='a'.repeat(43);
const frontend=publicOrigin||'http://127.0.0.1:8990';
try {
  server=await startServer({port:0,directory,publicOrigin,accessKey});
  context=await chromium.launchPersistentContext('',{channel:'chromium',headless:true,viewport:{width:1360,height:900},args:['--enable-unsafe-extension-debugging'],ignoreDefaultArgs:['--disable-extensions']});
  const page=await context.newPage(),errors=[];
  const testOrigin=`http://127.0.0.1:${server.address().port}`;
  if(remote){
    const config=JSON.parse(await readFile('deploy/mock-fap/vercel.json','utf8'));
    const headers=Object.fromEntries(config.headers[0].headers.map(h=>[h.key,h.value]));
    await page.route(frontend+'/**',async route=>{
      const pathname=new URL(route.request().url()).pathname;
      const name=pathname==='/'?'index.html':pathname.slice(1);
      assert.ok(['index.html','app.mjs','connection.mjs','style.css'].includes(name));
      await route.fulfill({headers,contentType:name.endsWith('.html')?'text/html':name.endsWith('.css')?'text/css':'text/javascript',body:await readFile('deploy/mock-fap/public/'+name)});
    });
  }
  await page.route((remote?'https://fap-backend-test.trycloudflare.com':frontend)+'/**',async route=>{
    const headers={...route.request().headers()};delete headers.host;
    if(headers.origin && !remote)headers.origin=testOrigin;
    if(remote){assert.equal(headers.origin,publicOrigin);assert.equal(headers.authorization,`Bearer ${accessKey}`);}
    const response=await route.fetch({url:testOrigin+new URL(route.request().url()).pathname,headers});
    await route.fulfill({response});
  });
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto(frontend+(remote?`/#api=https%3A%2F%2Ffap-backend-test.trycloudflare.com&key=${accessKey}`:''));
  await page.locator('#empty').waitFor();
  if(remote){assert.equal(new URL(page.url()).hash,'');checks.push('remote origin, bearer key and fragment removal');}
  await mkdir('build/previews',{recursive:true});
  await page.screenshot({path:'build/previews/phase4_mock_empty.png',fullPage:true});
  await page.locator('#import').setInputFiles('mock-fap/demo/FA26-demo.json');
  await page.locator('tr[data-roll]').first().waitFor();
  assert.deepEqual(await page.locator('select[data-mark]').evaluateAll(nodes=>nodes.map(n=>n.value)),['','','']);
  assert.equal(await page.locator('#stat-pending').textContent(),'3');
  const sessions=parseCsv(await readFile('mock-fap/demo/FA26-demo.csv','utf8'));
  const run=(s,submit=false,revision=null)=>page.evaluate(`(${interactWithMock.toString()})(${JSON.stringify(s)},${submit},${JSON.stringify(revision)},${JSON.stringify(publicOrigin)})`);
  assert.equal((await run(sessions[1])).ok,false);checks.push('wrong session blocked');
  assert.equal((await run({...sessions[0],students:sessions[0].students.slice(1)})).ok,false);checks.push('missing student blocked');
  assert.equal((await run({...sessions[0],students:sessions[0].students.map((s,i)=>i===0?{...s,roll:'SE999999'}:s)})).ok,false);checks.push('unknown student blocked');
  await page.locator('#students').evaluate(t=>t.prepend(t.lastElementChild));
  const preview=await run(sessions[0]);assert.equal(preview.ok,true);assert.equal(preview.present,2);checks.push('row reordering matched by MSSV');
  assert.equal((await run(sessions[0],true,'stale')).ok,false);checks.push('stale preview blocked');
  assert.deepEqual(await page.locator('select[data-mark]').evaluateAll(nodes=>nodes.map(n=>n.value)),['','','']);
  const browserCdp=await context.browser().newBrowserCDPSession();
  const {id}=await browserCdp.send('Extensions.loadUnpacked',{path:path.resolve('extension')});
  const {targetInfos}=await browserCdp.send('Target.getTargets',{filter:[{type:'tab',exclude:false}]});
  const targetInfo=targetInfos.find(t=>t.url===frontend+'/');
  assert.ok(targetInfo,JSON.stringify(targetInfos));
  await page.bringToFront();
  await browserCdp.send('Extensions.triggerAction',{id,targetId:targetInfo.targetId});
  // Run the shipped popup page in an extension tab; the real browser action
  // above grants activeTab. No Chrome API or host permission is stubbed.
  const popup=await context.newPage();
  await popup.goto(`chrome-extension://${id}/popup.html`);
  if(remote){
    await popup.locator('.connection-settings summary').click();
    await popup.locator('#mock-origin').fill(publicOrigin);
    await popup.locator('#save-origin').click();
    await popup.getByText('Đã lưu địa chỉ trang giả lập. Hãy đối chiếu lại CSV.',{exact:true}).waitFor();
  }
  await popup.locator('body').screenshot({path:'build/previews/phase4_extension_empty.png'});
  popup.on('pageerror',e=>errors.push(e.message));
  await popup.locator('#file').setInputFiles('mock-fap/demo/FA26-demo.csv');
  await page.bringToFront();
  await popup.locator('#preview').evaluate(button=>button.click());
  await popup.locator('#submit:not([disabled])').waitFor();
  await mkdir('build/previews',{recursive:true});
  await popup.locator('body').screenshot({path:'build/previews/phase4_extension_preview.png'});
  await popup.locator('#submit').evaluate(button=>button.click());
  await popup.getByText('Đã lưu thành công 3 sinh viên trên trang giả lập.',{exact:true}).waitFor();
  checks.push('real MV3 popup activeTab scripting fill and submit');
  const stored=JSON.parse(await readFile(path.join(directory,'mock-fa26.json'),'utf8'));
  assert.deepEqual(stored.records[sessions[0].id].marks,{SE000001:'P',SE000002:'A',SE000003:'P'});
  assert.equal(Object.keys(stored.records).length,1);checks.push('only chosen session saved');
  await popup.close();await page.reload();
  await page.locator('tr[data-roll]').first().waitFor();
  assert.equal(await page.locator('tr[data-roll="SE000002"] select').inputValue(),'A');checks.push('saved state survives reload');
  assert.equal(await page.locator('#stat-present').textContent(),'2');
  assert.equal(await page.locator('#stat-absent').textContent(),'1');
  assert.equal(await page.locator('#stat-pending').textContent(),'0');
  checks.push('live attendance counters match saved marks');
  await page.screenshot({path:'build/previews/phase4_mock_saved.png',fullPage:true});
  await page.setViewportSize({width:800,height:650});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);checks.push('800px layout without page overflow');
  await page.setViewportSize({width:390,height:844});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
  await page.screenshot({path:'build/previews/phase4_mock_mobile.png',fullPage:true});
  checks.push('390px layout without page overflow');
  const unchanged=await run(sessions[0]);assert.equal(unchanged.changed,0);
  const repeated=await run(sessions[0],true,unchanged.revision);assert.equal(repeated.submitted,true);
  assert.equal(JSON.parse(await readFile(path.join(directory,'mock-fa26.json'),'utf8')).revision,stored.revision);checks.push('repeat submit idempotent');
  await page.route('**/api/submit',route=>route.fulfill({status:500,headers:remote?{'Access-Control-Allow-Origin':publicOrigin}:{},contentType:'application/json',body:JSON.stringify({error:'Synthetic disk failure'})}));
  const failure=await run(sessions[0],true,unchanged.revision);assert.equal(failure.ok,false);assert.match(failure.error,/Synthetic disk failure/);checks.push('server failure not reported as success');
  assert.deepEqual(errors,[]);
  await writeFile(`build/previews/phase4-${remote?'vercel-':''}browser.json`,JSON.stringify({checks,pageErrors:errors},null,2));
  console.log('PASS: '+checks.join('; '));
} finally {
  await context?.close();if(server)await new Promise(r=>server.close(r));await rm(directory,{recursive:true,force:true});
}
