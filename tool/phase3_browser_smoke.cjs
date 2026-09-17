// Browser flow test with a stub Google button; real JWT verification has separate RSA tests.
const {chromium} = require('../build/browser-tools/node_modules/playwright');
const {spawn} = require('node:child_process');
const {createInterface} = require('node:readline');
const {once} = require('node:events');
const assert = require('node:assert/strict');
const fs = require('node:fs');
(async () => {
  const child = spawn('D:\\Flutter\\flutter\\bin\\cache\\dart-sdk\\bin\\dart.exe', ['tool/phase3_browser_host.dart'], {windowsHide:true, stdio:['pipe','pipe','inherit']});
  const lines = createInterface({input:child.stdout});
  const line = () => once(lines,'line').then(([v]) => JSON.parse(v));
  let browser;
  try {
    const setup = await line();
    browser = await chromium.launch({channel:'chrome', headless:true});
    const page = await browser.newPage({viewport:{width:390,height:844}});
    const errors = []; page.on('pageerror', e => errors.push(e.message));
    await page.route('https://accounts.google.com/gsi/client', route => route.fulfill({contentType:'text/javascript', body:`window.google={accounts:{id:{initialize(options){this.options=options},renderButton(target){const b=document.createElement('button');b.textContent='Google (test only)';b.onclick=()=>this.options.callback({credential:'test-google-response'});target.append(b)}}}};`}));
    await page.goto(setup.url);
    await page.getByText('Google (test only)').click();
    await page.locator('#attendance').waitFor({state:'visible'});
    assert.match(await page.locator('#identity').innerText(),/SE000001/);
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),true);
    await page.locator('#secret').fill('wrong!');
    // Native HTML pattern prevents malformed input; a valid-shaped wrong code reaches the server.
    await page.locator('#secret').fill(setup.secret==='000000'?'111111':'000000');
    await page.locator('#submit').click();
    await page.getByText('Mã bí mật không đúng.', {exact:false}).waitFor();
    await page.screenshot({path:'build/previews/phase3_student_form.png',fullPage:true});
    await page.locator('#secret').fill(setup.secret); await page.locator('#submit').click();
    await page.locator('#success').waitFor({state:'visible'});
    await page.screenshot({path:'build/previews/phase3_student_success.png',fullPage:true});
    const pending = line(); child.stdin.write('state\n'); const state = await pending;
    assert.equal(state.sessions[0].marks.SE000001,'P');
    assert.equal(state.history.at(-1).action,'qr_present');
    assert.deepEqual(errors,[]);
    await page.goto(new URL('/',setup.url).href);
    await page.getByText('Không có mã QR hợp lệ. Hãy quét lại.').waitFor();
    const result={browser:'Chrome headless',viewport:'390x844',google:'stub button; not real OAuth',wrongSecretRetry:true,persistCallback:true,missingQrRejected:true,pageErrors:errors};
    fs.writeFileSync('build/previews/phase3-browser.json',JSON.stringify(result,null,2));
    console.log('PASS: mobile browser layout, Google callback integration (stub), wrong secret retry, P saved, missing QR.');
  } finally {
    await browser?.close(); child.stdin.write('stop\n'); lines.close();
    setTimeout(()=>child.kill(),1000).unref();
  }
})().catch(error=>{console.error(error);process.exitCode=1});
