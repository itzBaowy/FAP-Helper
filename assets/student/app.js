'use strict';
(() => {
  const $ = id => document.getElementById(id);
  let scan;
  let timer;
  let completed = false;
  let signingIn = false;
  let apiOrigin = location.origin;
  const message = (text, error = false) => {
    $('message').textContent = text;
    $('message').className = error ? 'error' : '';
  };
  async function api(path, data) {
    const response = await fetch(apiOrigin + path, {method:'POST', headers:{'Content-Type':'application/json'},
      body:JSON.stringify(data), credentials:'omit', cache:'no-store', signal:AbortSignal.timeout(20000)});
    const result = await response.json();
    if (!response.ok) {
      const error = new Error(result.error || 'Yêu cầu chưa hoàn tất. Hãy thử lại.');
      error.status = response.status;
      throw error;
    }
    return result;
  }
  function failure(error) {
    message(error.name === 'TimeoutError' || error instanceof TypeError
      ? 'Mất kết nối hoặc chưa nhận được phản hồi. Hãy thử lại; hệ thống không ghi trùng điểm danh.' : error.message, true);
    if (error.status === 410) {
      $('login').hidden = true; $('attendance').hidden = true; clearInterval(timer);
      $('expiry').textContent = 'Quét QR mới nếu giảng viên vẫn đang nhận điểm danh.';
    }
  }
  async function googleCredential(result) {
    if (signingIn || completed) return;
    signingIn = true;
    message('Đang xác thực tài khoản Google…');
    try {
      const identity = await api('/api/login', {ticket:scan.ticket, credential:result.credential});
      $('identity').textContent = `${identity.fullName} · ${identity.rollNumber}\n${identity.email}`;
      $('login').hidden = true; $('attendance').hidden = false;
      $('secret-field').hidden = !scan.requiresSecret;
      $('secret').required = scan.requiresSecret;
      message('Kiểm tra thông tin rồi bấm xác nhận có mặt.');
    } catch (error) { failure(error); }
    finally { signingIn = false; }
  }
  $('attendance').addEventListener('submit', async event => {
    event.preventDefault();
    $('submit').disabled = true;
    message('Đang lưu điểm danh…');
    try {
      await api('/api/submit', {ticket:scan.ticket, secret:$('secret').value.trim()});
      completed = true; clearInterval(timer);
      $('attendance').hidden = true; $('success').hidden = false; $('expiry').textContent = ''; message('');
    } catch (error) { failure(error); }
    finally { $('submit').disabled = false; }
  });
  async function start() {
    const fragment = location.hash.slice(1);
    let qr = fragment;
    history.replaceState(null, '', location.pathname);
    if (fragment.startsWith('token=')) {
      const parameters = new URLSearchParams(fragment);
      qr = parameters.get('token') || '';
      const backend = parameters.get('api') || '';
      // Remote QR destinations are restricted to the teacher's Quick Tunnel.
      if (!/^https:\/\/[a-z0-9-]+\.trycloudflare\.com$/.test(backend) ||
          parameters.getAll('api').length !== 1 || parameters.getAll('token').length !== 1) {
        $('lesson').textContent = 'Địa chỉ kết nối không hợp lệ.';
        message('Hãy quét QR được tạo từ app giảng viên.', true); return;
      }
      apiOrigin = backend;
    }
    if (!/^[A-Za-z0-9_-]{43}$/.test(qr)) {
      $('lesson').textContent = 'Mở trang bằng mã QR trên màn hình giảng viên.';
      message('Không có mã QR hợp lệ. Hãy quét lại.', true); return;
    }
    try {
      // Exchange immediately: QR lives 15 s; the scanned ticket allows 3 min for Google login.
      scan = await api('/api/scan', {token:qr});
      $('lesson').textContent = `${scan.classLabel} · ${scan.sessionLabel}`;
      $('login').hidden = false; message('Quét thành công. Tiếp tục đăng nhập Google.');
      timer = setInterval(() => {
        const seconds = Math.max(0, Math.ceil((Date.parse(scan.expiresAt) - Date.now()) / 1000));
        $('expiry').textContent = `Còn ${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2,'0')} để hoàn tất lượt quét.`;
        if (seconds === 0 && !completed) failure(Object.assign(new Error('Lượt quét hết hạn. Hãy quét QR mới.'), {status:410}));
      }, 1000);
      const deadline = Date.now() + 15000;
      while (!window.google?.accounts?.id) {
        if (Date.now() > deadline) throw new Error('Chưa tải được đăng nhập Google. Kiểm tra Internet, mở bằng Chrome/Safari rồi quét lại QR.');
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      google.accounts.id.initialize({client_id:scan.clientId, callback:googleCredential, nonce:scan.nonce, auto_select:false});
      google.accounts.id.renderButton($('google-button'), {theme:'outline', size:'large', text:'signin_with', locale:'vi', width:Math.min(340, $('login').clientWidth)});
    } catch (error) { failure(error); }
  }
  start();
})();
