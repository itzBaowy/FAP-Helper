import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../assets/student/app.js', import.meta.url), 'utf8');

async function mount(submit) {
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
  let ready;
  const initialized = new Promise(resolve => { ready = resolve; });
  const google = {accounts: {id: {
    initialize(options) { credential = options.callback; ready(); },
    renderButton() {},
  }}};
  vm.runInNewContext(source, {
    document: {getElementById: get},
    location: {origin: 'http://localhost', hash: '#' + 'a'.repeat(43), pathname: '/'},
    history: {replaceState() {}},
    window: {google}, google,
    fetch: async (url, options) => {
      calls.push(url);
      if (url.endsWith('/api/scan')) return {ok: true, json: async () => ({ticket: 'ticket', nonce: 'nonce', expiresAt: new Date(Date.now() + 180000).toISOString()})};
      if (url.endsWith('/api/login')) return {ok: true, json: async () => ({fullName: 'Sinh viên giả', rollNumber: 'SE000001', email: 'an@example.com'})};
      return submit(JSON.parse(options.body));
    },
    AbortSignal, URLSearchParams, setTimeout, setInterval: () => 1, clearInterval() {},
  });
  await initialized;
  await credential({credential: 'test'});
  return {get, calls, send: () => get('attendance').submit({preventDefault() {}})};
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

test('Vercel copy stays identical to bundled student assets', async () => {
  for (const name of ['app.js', 'index.html', 'style.css']) {
    assert.equal(await readFile(new URL('../assets/student/' + name, import.meta.url), 'utf8'),
      await readFile(new URL('../deploy/student/public/' + name, import.meta.url), 'utf8'));
  }
});
