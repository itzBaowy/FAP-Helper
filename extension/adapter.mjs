// Self-contained for chrome.scripting.executeScript in the isolated world.
export async function interactWithMock(session, submit = false, expectedRevision = null, configuredOrigin = '') {
  try {
    const origins=['http://127.0.0.1:8990','http://localhost:8990'];
    if(/^https:\/\/[a-z0-9-]+\.vercel\.app$/.test(configuredOrigin))origins.push(configuredOrigin);
    if (!origins.includes(location.origin) ||
        document.querySelector('meta[name="fap-helper-mock"]')?.content !== '1') throw Error('Mở trang GV giả lập; nếu dùng Vercel, lưu đúng địa chỉ trong cấu hình extension.');
    const form = document.querySelector('#attendance-form');
    if (!form || form.dataset.session !== session.id || form.dataset.loading === 'true') throw Error('Buổi trên trang không khớp CSV. Chọn đúng môn, lớp, ngày và slot.');
    if (expectedRevision !== null && form.dataset.revision !== expectedRevision) throw Error('Trang đã thay đổi. Hãy đối chiếu lại.');
    if (form.dataset.busy === 'true') throw Error('Trang đang lưu điểm danh.');
    const rows = [...form.querySelectorAll('tr[data-roll]')];
    const csv = new Map(session.students.map(s => [s.roll,s.status]));
    if (!csv.size || csv.size !== session.students.length || rows.length !== csv.size || new Set(rows.map(r => r.dataset.roll)).size !== rows.length) throw Error('Số lượng sinh viên hoặc MSSV trùng/thiếu. Chưa điền dữ liệu.');
    const controls = rows.map(row => {
      const status = csv.get(row.dataset.roll), select = row.querySelector('select[data-mark]');
      if (!['P','A'].includes(status) || !select || select.disabled || ![...select.options].some(o => o.value === status)) throw Error('Danh sách MSSV trên trang không khớp CSV hoặc ô điểm danh bị khóa.');
      return {select, status};
    });
    const preview = {ok:true, revision:form.dataset.revision, count:rows.length,
      present:session.students.filter(s => s.status === 'P').length,
      absent:session.students.filter(s => s.status === 'A').length,
      changed:controls.filter(c => c.select.value !== c.status).length};
    if (!submit) return preview;
    const button = form.querySelector('button[type="submit"]');
    if (!button || button.disabled) throw Error('Nút submit chưa sẵn sàng.');
    for (const {select,status} of controls) {
      select.value = status;
      select.dispatchEvent(new Event('input', {bubbles:true}));
      select.dispatchEvent(new Event('change', {bubbles:true}));
    }
    const requestId = crypto.randomUUID();
    form.dataset.request = requestId;
    form.requestSubmit(button);
    const deadline = Date.now() + 12000;
    while (Date.now() < deadline) {
      if (!form.isConnected || form.dataset.session !== session.id) throw Error('Trang đã đổi buổi khi đang submit. Kiểm tra kết quả trên trang.');
      if (form.dataset.receipt === requestId) return {...preview, submitted:true};
      if (form.dataset.failed === requestId) throw Error(document.querySelector('#message')?.textContent || 'Trang báo lỗi lưu.');
      await new Promise(resolve => setTimeout(resolve,100));
    }
    throw Error('Chưa nhận được xác nhận lưu. Kiểm tra trang trước khi thử lại.');
  } catch (error) { return {ok:false, error:error.message}; }
}
