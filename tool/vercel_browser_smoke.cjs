// Tests separate static hosting using local stand-ins for Vercel/Cloudflare.
const {chromium} = require('../build/browser-tools/node_modules/playwright');
const {spawn} = require('node:child_process');
const {createInterface} = require('node:readline');
const {once} = require('node:events');
const assert = require('node:assert/strict');
const fs = require('node:fs');
(async () => {
  const child = spawn('D:\\Flutter\\flutter\\bin\\cache\\dart-sdk\\bin\\dart.exe', ['tool/phase3_browser_host.dart','--vercel'], {windowsHide:true, stdio:['pipe','pipe','inherit']});
  const lines = createInterface({input:child.stdout});
  const line = () => once(lines,'line').then(([v]) => JSON.parse(v));
  let browser;
  try {
    const setup = await line();
    browser = await chromium.launch({channel:'chrome', headless:true});
    const page = await browser.newPage({viewport:{width:390,height:844}});
    const errors=[];page.on('pageerror',e=>errors.push(e.message));
    const headers=Object.fromEntries(JSON.parse(fs.readFileSync('deploy/student/vercel.json')).headers[0].headers.map(h=>[h.key,h.value]));
    await page.route('https://student-test.vercel.app/**', async route => {
      const path=new URL(route.request().url()).pathname;
      const file={'/':'index.html','/app.js':'app.js','/style.css':'style.css'}[path];
      if(!file) return route.fulfill({status:404,body:''});
      await route.fulfill({headers,contentType:file.endsWith('.js')?'text/javascript':file.endsWith('.css')?'text/css':'text/html',body:fs.readFileSync('deploy/student/public/'+file)});
    });
    let apiCalls=0;
    await page.route('https://teacher-test.trycloudflare.com/**', async route => {
      apiCalls++;
      assert.equal(route.request().headers().origin,'https://student-test.vercel.app');
      const response=await route.fetch({url:setup.localOrigin+new URL(route.request().url()).pathname});
      assert.equal(response.headers()['access-control-allow-origin'],'https://student-test.vercel.app');
      await route.fulfill({response});
    });
    await page.route('https://accounts.google.com/gsi/client',route=>route.fulfill({contentType:'text/javascript',body:`window.google={accounts:{id:{initialize(o){this.o=o},renderButton(t){const b=document.createElement('button');b.textContent='Google test';b.onclick=()=>this.o.callback({credential:'test-google-response'});t.append(b)}}}};`}));
    await page.goto(setup.url);
    await page.getByText('Google test',{exact:true}).click();
    await page.locator('#attendance').waitFor({state:'visible'});
    await page.locator('#secret').fill(setup.secret);await page.locator('#submit').click();
    await page.locator('#success').waitFor({state:'visible'});
    assert.equal(new URL(page.url()).origin,'https://student-test.vercel.app');
    assert.equal(new URL(page.url()).hash,'');
    assert.ok(apiCalls>=3);
    const pending=line();child.stdin.write('state\n');assert.equal((await pending).sessions[0].marks.SE000001,'P');
    await page.screenshot({path:'build/previews/vercel_student_success.png',fullPage:true});
    const before=apiCalls;
    await page.goto('about:blank');
    await page.goto('https://student-test.vercel.app/#token='+('a'.repeat(43))+'&api='+encodeURIComponent('https://evil.example'));
    await page.getByText('Địa chỉ kết nối không hợp lệ.',{exact:true}).waitFor();
    assert.equal(apiCalls,before);assert.deepEqual(errors,[]);
    fs.writeFileSync('build/previews/vercel-browser.json',JSON.stringify({staticOriginFlow:true,google:'test stub',corsHeaders:true,untrustedBackendRejected:true,pageErrors:errors},null,2));
    console.log('PASS: separate static origin, CORS, Google callback stub, P saved, untrusted backend rejected.');
  } finally { await browser?.close();child.stdin.write('stop\n');lines.close();setTimeout(()=>child.kill(),1000).unref(); }
})().catch(e=>{console.error(e);process.exitCode=1});
