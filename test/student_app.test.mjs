import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../assets/student/app.js', import.meta.url), 'utf8');

async function mount(submit, {autoLogin = true, login, storage = new Map(), fragment = '#' + 'a'.repeat(43), resume} = {}) {
  let now = Date.now();
  let tick;
  const nodes = new Map();
  const get = id => {
    if (!nodes.has(id)) nodes.set(id, {
      hidden: true, disabled: false, value: '', clientWidth: 340, textContent: '',
      addEventListener(_, callback) { this.submit = callback; },
    });
    return nodes.get(id);
  };
  const calls = [];
  let credential;
  const google = {accounts: {id: {
    initialize(options) { credential = options.callback; },
    renderButton() {},
  }}};
  vm.runInNewContext(source, {
    document: {getElementById: get},
    location: {origin: 'http://localhost', hash: fragment, pathname: '/'},
    sessionStorage: {getItem: key => storage.get(key) ?? null, setItem: (key,value) => storage.set(key,value), removeItem: key => storage.delete(key)},
    history: {replaceState() {}},
    window: {google}, google,
    Date: {now: () => now, parse: Date.parse},
    fetch: async (url, options) => {
      calls.push(url);
      if (url.endsWith('/api/scan')) return {ok: true, json: async () => ({ticket: 't'.repeat(43), nonce: 'nonce', expiresAt: new Date(now + 180000).toISOString()})};
      if (url.endsWith('/api/resume')) {
        const result = await resume();
        return result.status ? {ok:false, status:result.status, json:async()=>result} : {ok:true, json:async()=>result};
      }
      if (url.endsWith('/api/login')) return {ok: true, json: async () => login ? login() : ({fullName: 'Sinh viên giả', rollNumber: 'SE000001', email: 'an@example.com'})};
      return submit(JSON.parse(options.body));
    },
    AbortSignal, URLSearchParams, setTimeout,
    setInterval(callback) { tick = callback; return 1; },
    clearInterval() { tick = undefined; },
  });
  await new Promise(setImmediate);
  const signIn = () => credential({credential: 'test'});
  if (autoLogin && credential) await signIn();
  return {
    get, calls, signIn, storage,
    advance(milliseconds) { now += milliseconds; tick?.(); },
    send: () => get('attendance').submit({preventDefault() {}}),
  };
}

test('concurrent submit events send once; duplicates show a clear receipt', async () => {
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const app = await mount(async () => {
    await gate;
    return {ok: true, json: async () => ({status: 'P', duplicate: true})};
  });
  const first = app.send();
  await app.send();
  assert.equal(app.calls.filter(url => url.endsWith('/api/submit')).length, 1);
  assert.equal(app.get('submit').disabled, true);
  release();
  await first;
  assert.equal(app.get('success-title').textContent, 'Bạn đã điểm danh trước đó');
  assert.equal(app.get('success').hidden, false);
  await app.send();
  assert.equal(app.calls.filter(url => url.endsWith('/api/submit')).length, 1);
});

test('failed saves stay retryable and never display success', async () => {
  let attempts = 0;
  const app = await mount(async () => ++attempts === 1
    ? {ok: false, status: 500, json: async () => ({error: 'Chưa lưu được'})}
    : {ok: true, json: async () => ({status: 'P', duplicate: false})});
  await app.send();
  assert.equal(app.get('success').hidden, true);
  assert.equal(app.get('submit').disabled, false);
  await app.send();
  assert.equal(app.get('success-title').textContent, 'Đã ghi nhận có mặt');
  assert.equal(app.get('submit').disabled, true);
});

test('an accepted scan continues through QR rotation with its own countdown', async () => {
  const app = await mount(async () => ({ok: true, json: async () => ({status: 'P'})}), {autoLogin: false});
  assert.match(app.get('message').textContent, /QR đổi không làm mất lượt/);
  assert.match(app.get('expiry').textContent, /3:00/);
  app.advance(15000);
  assert.match(app.get('expiry').textContent, /2:45/);
  await app.signIn();
  assert.equal(app.get('attendance').hidden, false);
  await app.send();
  assert.equal(app.get('success').hidden, false);
  assert.equal(app.calls.filter(url => url.endsWith('/api/scan')).length, 1);
});

test('login does not renew the scan deadline; callbacks and submits stop at three minutes', async () => {
  const app = await mount(async () => { throw new Error('Expired scans must not send'); }, {autoLogin: false});
  app.advance(170000);
  await app.signIn();
  assert.match(app.get('expiry').textContent, /0:10/);
  app.advance(10000);
  assert.equal(app.get('attendance').hidden, true);
  assert.equal(app.get('login').hidden, true);
  assert.match(app.get('message').textContent, /hết 3 phút/);
  await app.signIn();
  await app.send();
  assert.equal(app.calls.filter(url => url.endsWith('/api/login')).length, 1);
  assert.equal(app.calls.filter(url => url.endsWith('/api/submit')).length, 0);
});

test('a delayed login response cannot reopen an expired scan', async () => {
  let release;
  const identity = new Promise(resolve => { release = resolve; });
  const app = await mount(async () => {}, {autoLogin: false, login: () => identity});
  const pending = app.signIn();
  app.advance(180000);
  release({fullName: 'Sinh viên giả', rollNumber: 'SE000001', email: 'an@example.com'});
  await pending;
  assert.equal(app.get('attendance').hidden, true);
  assert.match(app.get('message').textContent, /hết 3 phút/);
});

test('an accepted submission can finish saving after the local countdown ends', async () => {
  let release;
  const saved = new Promise(resolve => { release = resolve; });
  const app = await mount(async () => {
    await saved;
    return {ok: true, json: async () => ({status: 'P'})};
  });
  app.advance(179999);
  const pending = app.send();
  app.advance(1);
  release();
  await pending;
  assert.equal(app.get('success').hidden, false);
  assert.equal(app.get('expiry').textContent, '');
});

test('reload restores the server ticket and authenticated step without renewing its deadline', async () => {
  const first = await mount(async () => {}, {autoLogin:false});
  const stored = JSON.parse(first.storage.get('fap-student-scan-v1'));
  assert.deepEqual(Object.keys(stored).sort(), ['api', 'ticket']);
  const restored = await mount(async () => ({ok:true,json:async()=>({status:'P'})}), {
    fragment:'', storage:first.storage,
    resume:async()=>({ticket:stored.ticket, nonce:'nonce', serverTime:'2026-10-21T03:02:00Z', expiresAt:'2026-10-21T03:03:00Z', identity:{fullName:'Sinh viên giả',rollNumber:'SE000001',email:'an@example.com'}}),
  });
  assert.match(restored.get('expiry').textContent, /1:00/);
  assert.equal(restored.get('attendance').hidden, false);
  assert.equal(restored.calls.some(url=>url.endsWith('/api/scan')), false);
  await restored.send();
  assert.equal(restored.get('success').hidden, false);
});

test('reload of an expired or stopped ticket clears it and requires a new scan', async () => {
  const first = await mount(async () => {}, {autoLogin:false});
  const restored = await mount(async () => {}, {
    fragment:'', storage:first.storage,
    resume:async()=>({status:410,error:'Lượt quét đã hết hạn.'}),
  });
  assert.equal(restored.storage.has('fap-student-scan-v1'), false);
  assert.equal(restored.get('attendance').hidden, true);
  assert.equal(restored.get('login').hidden, true);
  assert.match(restored.get('message').textContent, /hết hạn/);
});

test('reload restores an already saved receipt without submitting again', async () => {
  const first = await mount(async () => {}, {autoLogin:false});
  const restored = await mount(async () => { throw Error('Must not submit'); }, {
    fragment:'', storage:first.storage,
    resume:async()=>({ticket:'t'.repeat(43),nonce:'nonce',expiresAt:new Date(Date.now()+60000).toISOString(),submitted:true}),
  });
  assert.equal(restored.get('success').hidden, false);
  assert.equal(restored.calls.filter(url=>url.endsWith('/api/submit')).length, 0);
});

test('Vercel copy stays identical to bundled student assets', async () => {
  for (const name of ['app.js', 'index.html', 'style.css']) {
    assert.equal(await readFile(new URL('../assets/student/' + name, import.meta.url), 'utf8'),
      await readFile(new URL('../deploy/student/public/' + name, import.meta.url), 'utf8'));
  }
});
