import { requestApi, requestFile, connectLink } from "./connection.mjs";
import { parseXlsx, SLOT_TIMES } from "./xlsx-importer.mjs";
import {
  DraftStore,
  rosterMarks,
  changedCount,
  mergeDraft,
  matchesStudent,
  defaultSession,
} from "./workspace.mjs";
import {
  buildReport,
  reportCsv,
  downloadText,
  vietnamTime,
} from "./reports.mjs";

const $ = (id) => document.getElementById(id);
const form = $("attendance-form");
let state = null,
  busy = false,
  connected = false,
  polling = false;
let selected = { group: "", session: "" },
  base = {},
  marks = {},
  conflicts = new Set(),
  draftRevision = 0,
  drafts = null,
  scope = "";
let qr = null,
  clockOffset = 0;
let policyDrafts = Object.create(null),
  policyDirty = false;
const labels = {
  planned: "Chưa mở",
  open: "Đang điểm danh",
  closed: "Đã chốt",
  cancelled: "Buổi nghỉ",
};
const dayPairs = { 1: "Thứ 2 + Thứ 5", 2: "Thứ 3 + Thứ 6", 3: "Thứ 4 + Thứ 7" };
const weekday = (value) =>
  ["Chủ nhật", "Thứ 2", "Thứ 3", "Thứ 4", "Thứ 5", "Thứ 6", "Thứ 7"][
    new Date(`${value}T00:00:00Z`).getUTCDay()
  ];
const today = () =>
  new Date(Date.now() + 7 * 3600000).toISOString().slice(0, 10);
const group = () => state?.groups.find((g) => g.id === selected.group);
const session = () => state?.sessions.find((s) => s.id === selected.session);
const windows = () => state?.mode === "windows";
const dirty = () => changedCount(base, marks);
function message(text, error = false) {
  $("message").textContent = text;
  $("message").classList.toggle("error", error);
}
function remember() {
  if (selected.session && drafts)
    drafts.put(selected.session, base, marks, draftRevision, [...conflicts]);
}
function rememberPolicy() {
  try {
    sessionStorage.setItem(
      "fap-teacher-policy-v1/" + scope,
      JSON.stringify(policyDrafts),
    );
  } catch {}
}
function policyChanged() {
  const course = group();
  if (!course) return;
  const values = {
    total: $("planned-total").value,
    warning: $("warning-threshold").value,
  };
  policyDirty =
    values.total !== String(course.plannedTotal ?? "") ||
    values.warning !== String(course.absenceWarningPercent ?? "");
  if (policyDirty) policyDrafts[course.id] = values;
  else delete policyDrafts[course.id];
  rememberPolicy();
  $("report-note").textContent = policyDirty
    ? "Có cấu hình lớp chưa lưu. Giá trị được giữ trong tab này; bấm Lưu cấu hình lớp để áp dụng."
    : $("report-note").textContent;
}
function setConnected(value) {
  connected = value;
  $("connection-status").textContent = value
    ? "Đã kết nối máy GV"
    : "Mất kết nối · bản nháp được giữ";
  lock(busy);
}
function lock(value) {
  busy = value;
  for (const id of ["import", "group", "session", "connect", "retry"])
    $(id).disabled = value || (id === "import" && !connected);
  for (const select of document.querySelectorAll("select[data-mark]"))
    select.disabled = value || (windows() && session()?.state === "planned");
  form.dataset.busy = String(value);
  form.querySelector('button[type="submit"]').disabled =
    value ||
    !connected ||
    conflicts.size > 0 ||
    (windows() && session()?.state === "planned");
  $("discard").disabled = value || !dirty();
  for (const id of ["planned-total", "warning-threshold", "save-policy"])
    $(id).disabled = !windows() || value || !connected;
  renderControls();
}
function ask(title, description, choices, input = null) {
  const dialog = $("action-dialog");
  if (dialog.open) return Promise.resolve({ value: "cancel", text: "" });
  $("dialog-title").textContent = title;
  $("dialog-message").textContent = description;
  $("dialog-input-label").hidden = !input;
  $("dialog-label").textContent = input?.label ?? "";
  const field = $("dialog-input");
  field.value = input?.initial ?? "";
  field.type = input?.type ?? "text";
  field.required = !!input?.required;
  field.minLength = input?.minLength ?? 0;
  field.removeAttribute("min");
  field.removeAttribute("max");
  if (input?.min != null) field.min = input.min;
  if (input?.max != null) field.max = input.max;
  $("dialog-actions").replaceChildren();
  for (const choice of choices) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = choice.label;
    button.className = choice.danger
      ? "danger"
      : choice.value === "cancel"
        ? "secondary"
        : "";
    button.addEventListener("click", () => {
      if (input && choice.value !== "cancel" && !field.reportValidity()) return;
      dialog.close(choice.value);
    });
    $("dialog-actions").append(button);
  }
  return new Promise((resolve) => {
    dialog.addEventListener(
      "close",
      () => resolve({ value: dialog.returnValue, text: field.value.trim() }),
      { once: true },
    );
    dialog.returnValue = "cancel";
    dialog.showModal();
  });
}
async function guardNavigation({ allowDraft = true } = {}) {
  if (!dirty() && !policyDirty) return true;
  remember();
  const response = await ask(
    "Bạn có thay đổi chưa lưu",
    `${dirty()} thay đổi điểm danh${policyDirty ? " và cấu hình lớp chưa lưu" : ""} tại ${group()?.subject} · ${group()?.classCode}, ${session()?.date}. Bản nháp chỉ nằm trong phiên trình duyệt cho tới khi lưu thành công.`,
    [
      { value: "cancel", label: "Ở lại" },
      ...(allowDraft
        ? [{ value: "draft", label: "Giữ bản nháp và chuyển" }]
        : []),
      { value: "save", label: "Lưu và chuyển" },
    ],
  );
  if (response.value === "draft") return true;
  if (response.value !== "save") return false;
  if (dirty() && !(await saveChanges())) return false;
  return !policyDirty || (await savePolicy());
}
function updateStats() {
  $("stat-total").textContent = Object.keys(marks).length;
  $("stat-present").textContent = Object.values(marks).filter(
    (v) => v === "P",
  ).length;
  $("stat-absent").textContent = Object.values(marks).filter(
    (v) => v === "A",
  ).length;
  $("stat-pending").textContent = Object.values(marks).filter((v) => !v).length;
  const record = state?.records[selected.session];
  $("saved").textContent = dirty()
    ? `${dirty()} thay đổi chưa lưu`
    : record?.savedAt
      ? `Đã lưu lúc ${vietnamTime(record.savedAt)}`
      : "Chưa có điểm danh đã lưu";
  $("draft-status").textContent =
    drafts?.persistent === false
      ? "Trình duyệt không cho giữ bản nháp khi tải lại. Hãy lưu trước khi rời trang."
      : dirty()
        ? "Bản nháp được giữ trong tab này. Chưa ghi vào máy GV."
        : "Dữ liệu hiển thị khớp lần xác nhận của máy GV.";
  $("conflicts").hidden = conflicts.size === 0;
  $("conflict-message").textContent =
    `${conflicts.size} sinh viên có thay đổi đồng thời. Đối chiếu trước khi lưu; chưa ghi đè kết quả trên máy GV.`;
  for (const row of $("students").rows) {
    row.classList.toggle("conflict-row", conflicts.has(row.dataset.roll));
    row.querySelector("select").dataset.status = marks[row.dataset.roll];
  }
  filterRows();
  lock(busy);
}
function filterRows() {
  const course = group();
  if (!course) return;
  const filter = $("status-filter").value,
    query = $("search").value;
  let visible = 0;
  const byRoll = new Map(
    course.students.map((student) => [student.roll, student]),
  );
  for (const row of $("students").rows) {
    const student = byRoll.get(row.dataset.roll);
    row.hidden =
      !matchesStudent(student, query) ||
      (filter !== "all" && marks[student.roll] !== filter);
    if (!row.hidden) visible++;
  }
  $("visible-count").textContent =
    `${visible}/${course.students.length} sinh viên`;
  $("no-results").hidden = visible > 0;
  for (const button of document.querySelectorAll("[data-filter]"))
    button.setAttribute(
      "aria-pressed",
      String(button.dataset.filter === filter),
    );
}
function renderGroups() {
  const previous = selected.group;
  $("group").replaceChildren();
  for (const course of state?.groups ?? [])
    $("group").add(
      new Option(
        `${course.subject} · ${course.classCode} · ${dayPairs[course.dayPair] ?? "Lịch đã lưu"} · Slot ${course.slotNumber ?? "—"}`,
        course.id,
      ),
    );
  if (state?.groups.some((g) => g.id === previous)) $("group").value = previous;
  selected.group = $("group").value;
  const hasGroups = !!state?.groups.length;
  $("workspace").hidden = !hasGroups;
  $("empty").hidden = hasGroups || !connected;
  renderSessions();
}
function renderSessions() {
  const options = (state?.sessions ?? []).filter(
    (s) => s.groupId === selected.group,
  );
  $("session").replaceChildren();
  for (const item of options)
    $("session").add(
      new Option(
        `${item.date} · ${weekday(item.date)} · Slot ${item.slot} (${SLOT_TIMES[item.slot]})${item.isMakeup ? " · Học bù" : ""} · ${labels[item.state] ?? ""}`,
        item.id,
      ),
    );
  $("session").value = defaultSession(
    options,
    state?.today ?? today(),
    selected.session,
  );
  selected.session = $("session").value;
  renderRows();
  try {
    sessionStorage.setItem(
      "fap-teacher-selection-v1/" + scope,
      JSON.stringify(selected),
    );
  } catch {}
  renderQr(qr);
}
function renderRows() {
  const item = session(),
    course = group();
  const changedSession = form.dataset.session !== selected.session;
  form.hidden = !item;
  form.dataset.session = selected.session;
  form.dataset.revision = String(state?.revision ?? 0);
  if (changedSession) {
    delete form.dataset.receipt;
    delete form.dataset.failed;
    delete form.dataset.request;
  }
  $("students").replaceChildren();
  if (!item || !course) {
    base = {};
    marks = {};
    conflicts = new Set();
    renderControls();
    return;
  }
  const record = state.records[item.id],
    remote = rosterMarks(course.students, record?.marks);
  const draft = drafts?.get(item.id);
  const merged = draft
    ? mergeDraft(draft.base, draft.marks, remote)
    : { marks: remote, conflicts: [] };
  base = { ...remote };
  marks = { ...merged.marks };
  conflicts = new Set([
    ...merged.conflicts,
    ...(draft?.conflicts ?? []).filter((roll) => marks[roll] !== remote[roll]),
  ]);
  draftRevision = state.revision;
  remember();
  $("title").textContent = `${course.subject} · ${course.classCode}`;
  $("detail").textContent =
    `${weekday(item.date)}, ${item.date} · Slot ${item.slot} (${SLOT_TIMES[item.slot]})`;
  $("count").textContent = `${course.students.length} sinh viên`;
  $("session-state").textContent = labels[item.state] ?? "Buổi học";
  for (const [index, student] of course.students.entries()) {
    const row = document.createElement("tr");
    row.dataset.roll = student.roll;
    for (const text of [
      index + 1,
      student.roll,
      student.name,
      student.memberCode,
      student.email,
    ]) {
      const td = document.createElement("td");
      td.textContent = text;
      row.append(td);
    }
    if (windows()) {
      const history = document.createElement("button");
      history.type = "button";
      history.className = "student-history";
      history.textContent = "Xem lịch sử";
      history.addEventListener("click", () => showHistory(student));
      row.cells[2].append(history);
    }
    const td = document.createElement("td"),
      select = document.createElement("select");
    select.dataset.mark = "";
    select.setAttribute("aria-label", `Điểm danh ${student.roll}`);
    for (const [value, label] of [
      ["", "Chưa ghi nhận"],
      ["P", "P · Có mặt"],
      ["A", "A · Vắng"],
    ])
      select.add(new Option(label, value));
    select.value = marks[student.roll];
    select.addEventListener("change", () => {
      marks[student.roll] = select.value;
      conflicts.delete(student.roll);
      remember();
      updateStats();
    });
    td.append(select);
    const info = record?.details?.[student.roll];
    if (info) {
      const detail = document.createElement("small");
      detail.className = "mark-meta";
      detail.textContent = `${info.source} · ${vietnamTime(info.at)}`;
      td.append(detail);
    }
    row.append(td);
    $("students").append(row);
  }
  renderReport();
  updateStats();
}
function applyState(next) {
  remember();
  state = next;
  if (next?.serverTime) clockOffset = Date.parse(next.serverTime) - Date.now();
  const nextScope = `${location.origin}/${state?.mode ?? "mock"}/${state?.workspaceId ?? state?.term ?? "FA26"}`;
  if (scope !== nextScope) {
    scope = nextScope;
    let storage;
    policyDrafts = Object.create(null);
    try {
      storage = sessionStorage;
      const choice = JSON.parse(
        storage.getItem("fap-teacher-selection-v1/" + scope) || "null",
      );
      if (
        choice &&
        typeof choice.group === "string" &&
        typeof choice.session === "string"
      )
        selected = choice;
      const policies = JSON.parse(
        storage.getItem("fap-teacher-policy-v1/" + scope) || "{}",
      );
      if (policies && typeof policies === "object")
        for (const [id, value] of Object.entries(policies))
          if (
            value &&
            typeof value.total === "string" &&
            typeof value.warning === "string" &&
            /^\d{0,3}$/.test(value.total) &&
            /^\d{0,3}$/.test(value.warning)
          )
            policyDrafts[id] = value;
    } catch {
      storage = {
        getItem() {
          throw Error();
        },
        setItem() {
          throw Error();
        },
      };
    }
    drafts = new DraftStore(storage, "fap-teacher-drafts-v1/" + scope);
  }
  $("source-label").textContent = windows()
    ? "Windows · nguồn dữ liệu chính"
    : "Giả lập · dữ liệu riêng";
  setConnected(true);
  renderGroups();
  renderQr(next?.qr ?? null);
}
function renderControls() {
  const item = session();
  $("collection-controls").hidden = !windows() || !item;
  if (!windows() || !item) return;
  const matching =
    qr?.active &&
    qr.groupId === selected.group &&
    `FA26/${selected.group}/${qr.sessionId}` === selected.session;
  const ready = !busy && connected;
  $("open-session").hidden = item.state !== "planned";
  $("open-session").disabled = !ready || !item.canOpen;
  $("start-qr").hidden = item.state !== "open" || matching;
  $("start-qr").disabled = !ready || !!qr?.active || !!qr?.busy;
  $("stop-qr").hidden = !matching;
  $("stop-qr").disabled = !ready;
  $("close-session").hidden = item.state !== "open";
  $("close-session").disabled = !ready;
  $("export-session").disabled = !ready || item.state !== "closed";
  $("require-secret").disabled = busy || !!qr?.active;
  $("collection-status").textContent =
    qr?.error ??
    (qr?.active && !matching
      ? `QR đang nhận ở ${qr.groupId}. Dừng đợt đó trước khi chuyển lớp.`
      : item.state === "planned" && !item.canOpen
        ? "Chưa đến giờ mở buổi."
        : item.state === "closed"
          ? "Đã chốt. Sửa kết quả cần lý do và được ghi lịch sử."
          : "Lưu P/A không tự chốt buổi; ô trống chỉ chuyển A khi xác nhận chốt.");
}
function renderQr(value) {
  qr = value;
  const matching =
    !!qr?.active &&
    qr.groupId === selected.group &&
    `FA26/${selected.group}/${qr.sessionId}` === selected.session;
  $("qr-panel").hidden = !matching;
  $("roster-area").hidden = matching && !$("show-roster").checked;
  $("workspace").classList.toggle(
    "qr-active",
    matching && $("show-roster").checked,
  );
  if (matching) {
    const image = "data:image/svg+xml;base64," + btoa(qr.svg ?? "");
    if ($("qr-image").src !== image) $("qr-image").src = image;
    $("qr-progress").textContent =
      `${qr.activeScans} lượt quét còn hạn · ${qr.verifiedStudents} SV đã xác thực · ${qr.savedPresent} P đã lưu`;
    $("qr-secret").hidden = !qr.requiresSecret;
    $("qr-secret").textContent = qr.requiresSecret
      ? `Mã bí mật: ${qr.secret}`
      : "";
    updateQrClock();
  }
  renderControls();
}
function updateQrClock() {
  if (qr?.active)
    $("qr-expiry").textContent =
      `Đổi QR sau ${Math.max(0, Math.ceil((Date.parse(qr.expiresAt) - Date.now() - clockOffset) / 1000))} giây`;
}
function renderReport() {
  const course = group();
  if (!course) return;
  const draft = policyDrafts[course.id];
  $("planned-total").value = draft?.total ?? course.plannedTotal ?? "";
  $("warning-threshold").value =
    draft?.warning ?? course.absenceWarningPercent ?? "";
  policyDirty = !!draft;
  $("report-note").textContent =
    course.requiredTotal == null && course.plannedTotal == null
      ? "Chưa xác định tổng số buổi: chưa tính tỷ lệ vắng. Cấu hình ngưỡng là tùy chọn của GV."
      : `Tỷ lệ vắng = số A đã lưu / ${course.requiredTotal ?? course.plannedTotal} buổi phải học × 100%. Cảnh báo không tự kết luận điều kiện dự thi.`;
  if (policyDirty) $("report-note").textContent += " Có cấu hình lớp chưa lưu.";
  $("report-students").replaceChildren();
  for (const student of buildReport(state, course)) {
    const row = document.createElement("tr");
    for (const value of [
      student.roll,
      student.name,
      student.present,
      student.absent,
      student.percent == null ? "—" : `${student.percent.toFixed(1)}%`,
      student.warning ? "Đạt ngưỡng GV cấu hình" : "—",
    ]) {
      const td = document.createElement("td");
      td.textContent = value;
      row.append(td);
    }
    if (student.warning) row.className = "warning";
    $("report-students").append(row);
  }
}
async function showHistory(student) {
  const groupId = selected.group;
  let cursor = null;
  const events = [];
  const names = {
    mark: "Thủ công",
    qr_present: "QR · Google",
    correct: "Sửa sau chốt",
    close_absent: "Chốt ô trống thành A",
  };
  try {
    do {
      const page = await requestApi(
        `/api/history?groupId=${encodeURIComponent(groupId)}&roll=${encodeURIComponent(student.roll)}${cursor == null ? "" : "&before=" + cursor}`,
      );
      events.push(...page.events);
      cursor = page.nextCursor;
      const text = events.length
        ? events
            .map(
              (event) =>
                `${vietnamTime(event.at)} · ${event.sessionId}\n${names[event.action] ?? event.action}: ${event.before ?? "—"} → ${event.after ?? "—"}${event.reason ? "\nLý do: " + event.reason : ""}`,
            )
            .join("\n\n")
        : "Chưa có thay đổi đã lưu của sinh viên này.";
      const response = await ask(`${student.name} · ${student.roll}`, text, [
        { value: "cancel", label: "Đóng" },
        ...(cursor == null
          ? []
          : [{ value: "more", label: "Xem lịch sử cũ hơn" }]),
      ]);
      if (response.value !== "more") break;
    } while (cursor != null);
  } catch (error) {
    message(error.message, true);
  }
}
async function saveChanges() {
  if (busy || !session()) return false;
  if (!connected) {
    message("Chưa kết nối máy GV. Bản nháp được giữ.", true);
    return false;
  }
  if (conflicts.size) {
    message("Đối chiếu các dòng thay đổi đồng thời trước khi lưu.", true);
    return false;
  }
  if (!windows() && Object.values(marks).some((value) => !value)) {
    message(
      "Còn sinh viên chưa ghi nhận. Hoàn tất P/A cho toàn bộ lớp trước khi lưu ở chế độ giả lập.",
      true,
    );
    return false;
  }
  const sessionId = selected.session,
    revision = draftRevision,
    submitted = { ...marks };
  let reason = "";
  if (windows() && session().state === "closed" && dirty()) {
    const reply = await ask(
      "Sửa điểm danh sau khi chốt",
      "Nêu lý do sửa. Kết quả trước/sau và lý do được lưu vào lịch sử.",
      [
        { value: "cancel", label: "Hủy" },
        { value: "confirm", label: "Lưu sửa đổi" },
      ],
      { label: "Lý do", required: true, minLength: 3 },
    );
    if (reply.value !== "confirm") return false;
    reason = reply.text;
  }
  const requestId = form.dataset.request || crypto.randomUUID();
  lock(true);
  delete form.dataset.receipt;
  delete form.dataset.failed;
  message("Đang lưu điểm danh vào máy GV…");
  try {
    const next = await requestApi("/api/submit", {
      sessionId,
      marks: submitted,
      revision,
      reason,
    });
    drafts.remove(sessionId);
    base = submitted;
    marks = submitted;
    applyState(next);
    form.dataset.receipt = requestId;
    message(`Đã lưu thành công ${Object.keys(submitted).length} sinh viên.`);
    return true;
  } catch (error) {
    form.dataset.failed = requestId;
    message(error.message, true);
    if (error.status === 409) await reload();
    else if (!error.status) setConnected(false);
    return false;
  } finally {
    lock(false);
  }
}
async function reload() {
  if (polling) return;
  polling = true;
  try {
    const next = await requestApi("/api/state");
    applyState(next);
    message(
      state?.groups.length
        ? "Dữ liệu đã tải. Chọn lớp và buổi cần điểm danh."
        : "Import Excel để bắt đầu.",
    );
  } catch (error) {
    setConnected(false);
    message(error.message, true);
  } finally {
    polling = false;
  }
}
async function action(name) {
  if (busy || !session()) return;
  if ((dirty() || policyDirty) && !(await guardNavigation())) return;
  if (name === "close") {
    const course = group(),
      saved = state.records[selected.session]?.marks ?? {};
    const blank = course.students.filter(
      (student) => !saved[student.roll],
    ).length;
    const result = await ask(
      "Chốt danh sách toàn lớp?",
      `${course.subject} · ${course.classCode}\n${session().date} · Slot ${session().slot}\n${blank} sinh viên chưa ghi nhận sẽ chuyển A, kể cả người đang bị bộ lọc ẩn. QR và các lượt chưa gửi sẽ dừng.`,
      [
        { value: "cancel", label: "Ở lại" },
        { value: "confirm", label: "Xác nhận chốt", danger: true },
      ],
    );
    if (result.value !== "confirm") return;
  }
  lock(true);
  try {
    applyState(
      await requestApi("/api/action", {
        action: name,
        sessionId: selected.session,
        revision: state.revision,
        requireSecret: $("require-secret").checked,
      }),
    );
    message(
      name === "close"
        ? "Đã chốt và lưu kết quả toàn lớp."
        : "Đã cập nhật trạng thái buổi học.",
    );
  } catch (error) {
    message(error.message, true);
    if (error.status === 409) await reload();
    else if (!error.status) setConnected(false);
  } finally {
    lock(false);
  }
}
$("group").addEventListener("change", async () => {
  const next = $("group").value;
  $("group").value = selected.group;
  if (!(await guardNavigation())) return;
  $("group").value = next;
  selected.group = next;
  selected.session = "";
  renderSessions();
});
$("session").addEventListener("change", async () => {
  const next = $("session").value;
  $("session").value = selected.session;
  if (!(await guardNavigation())) return;
  selected.session = next;
  $("session").value = next;
  renderRows();
  renderQr(qr);
});
$("search").addEventListener("input", filterRows);
$("status-filter").addEventListener("change", filterRows);
for (const button of document.querySelectorAll("[data-filter]"))
  button.addEventListener("click", () => {
    $("status-filter").value = button.dataset.filter;
    filterRows();
  });
form.addEventListener("submit", (event) => {
  event.preventDefault();
  saveChanges();
});
$("discard").addEventListener("click", async () => {
  if (busy || !dirty()) return;
  const response = await ask(
    "Bỏ các thay đổi chưa lưu?",
    `${dirty()} thay đổi sẽ được thay bằng kết quả đã lưu trên máy GV.`,
    [
      { value: "cancel", label: "Ở lại" },
      { value: "confirm", label: "Bỏ thay đổi", danger: true },
    ],
  );
  if (response.value === "confirm") {
    drafts.remove(selected.session);
    renderRows();
  }
});
$("use-server").addEventListener("click", async () => {
  const response = await ask(
    "Dùng kết quả trên máy GV?",
    "Bỏ toàn bộ bản nháp của buổi đang chọn và dùng kết quả đã lưu.",
    [
      { value: "cancel", label: "Ở lại" },
      { value: "confirm", label: "Dùng máy GV" },
    ],
  );
  if (response.value === "confirm") {
    drafts.remove(selected.session);
    renderRows();
  }
});
$("keep-draft").addEventListener("click", async () => {
  const response = await ask(
    "Giữ bản nháp đã đối chiếu?",
    `${conflicts.size} dòng đang xung đột: ${[...conflicts].join(", ")}. Sau khi xác nhận, bấm Lưu để ghi kết quả bản nháp lên phiên bản mới nhất.`,
    [
      { value: "cancel", label: "Kiểm tra lại" },
      { value: "confirm", label: "Đã đối chiếu, giữ bản nháp" },
    ],
  );
  if (response.value === "confirm") {
    conflicts.clear();
    remember();
    updateStats();
  }
});
window.addEventListener("beforeunload", (event) => {
  remember();
  rememberPolicy();
  if (dirty() || policyDirty) {
    event.preventDefault();
    event.returnValue = "";
  }
});
$("retry").addEventListener("click", reload);
$("connect").addEventListener("click", async () => {
  if (!(await guardNavigation())) return;
  const response = await ask(
    "Kết nối máy giảng viên",
    "Trong app Windows: Cấu hình → Kết nối web GV → Sao chép liên kết. Chỉ dùng liên kết GV; không dùng liên kết QR của SV.",
    [
      { value: "cancel", label: "Hủy" },
      { value: "confirm", label: "Kết nối" },
    ],
    { label: "Liên kết riêng của giảng viên", required: true },
  );
  if (response.value !== "confirm") return;
  try {
    connectLink(response.text);
    await reload();
  } catch (error) {
    message(error.message, true);
  }
});
for (const [id, name] of [
  ["open-session", "open"],
  ["start-qr", "start-qr"],
  ["stop-qr", "stop-qr"],
  ["close-session", "close"],
])
  $(id).addEventListener("click", () => action(name));
$("show-roster").addEventListener("change", () => renderQr(qr));
$("import").addEventListener("change", async () => {
  if (busy) return;
  const file = $("import").files[0];
  if (!file) return;
  if (!(await guardNavigation({ allowDraft: false }))) {
    $("import").value = "";
    return;
  }
  lock(true);
  try {
    const isXlsx = file.name.toLowerCase().endsWith(".xlsx");
    if (!isXlsx && file.size > 10 * 1024 * 1024)
      throw Error("File JSON vượt quá 10 MB.");
    const parsed = isXlsx
      ? await parseXlsx(file)
      : { book: JSON.parse(await file.text()), warnings: [] };
    const next = await requestApi("/api/import", {
      book: parsed.book,
      revision: state?.revision ?? null,
    });
    applyState(next);
    message(
      `Đã nhập ${state.groups.length} lớp, ${state.sessions.length} buổi và ${state.groups.reduce((sum, course) => sum + course.students.length, 0)} lượt sinh viên từ ${file.name}.${parsed.warnings.length ? " Cảnh báo: " + parsed.warnings.map((item) => item.message).join(" ") : ""}`,
    );
  } catch (error) {
    message(error.message, true);
  } finally {
    lock(false);
    $("import").value = "";
  }
});
for (const id of ["planned-total", "warning-threshold"])
  $(id).addEventListener("input", policyChanged);
async function savePolicy() {
  if (busy || !windows() || !connected) return false;
  for (const id of ["planned-total", "warning-threshold"])
    if (!$(id).reportValidity()) return false;
  const total =
      $("planned-total").value === "" ? null : Number($("planned-total").value),
    warning =
      $("warning-threshold").value === ""
        ? null
        : Number($("warning-threshold").value);
  lock(true);
  try {
    applyState(
      await requestApi("/api/action", {
        action: "set-total",
        groupId: selected.group,
        value: total,
        revision: state.revision,
      }),
    );
    applyState(
      await requestApi("/api/action", {
        action: "set-warning",
        groupId: selected.group,
        value: warning,
        revision: state.revision,
      }),
    );
    delete policyDrafts[selected.group];
    policyDirty = false;
    rememberPolicy();
    renderReport();
    message("Đã lưu cấu hình chuyên cần của lớp.");
    return true;
  } catch (error) {
    message(error.message, true);
    return false;
  } finally {
    lock(false);
  }
}
$("save-policy").addEventListener("click", savePolicy);
$("export-report").addEventListener("click", () => {
  const course = group();
  if (course)
    downloadText(
      reportCsv(course, buildReport(state, course)),
      `FA26_${course.subject}_${course.classCode}_chuyen-can.csv`,
    );
});
$("export-session").addEventListener("click", async () => {
  if (busy) return;
  lock(true);
  try {
    downloadText(
      await requestFile(
        "/api/export?sessionId=" + encodeURIComponent(selected.session),
      ),
      `FA26_${group().subject}_${group().classCode}_${session().date}.csv`,
    );
  } catch (error) {
    message(error.message, true);
  } finally {
    lock(false);
  }
});
setInterval(async () => {
  if (document.hidden || busy || polling || !connected) return;
  polling = true;
  try {
    const next = await requestApi(
      windows() ? `/api/state?revision=${state.revision}` : "/api/state",
    );
    if (next?.unchanged) {
      if (next.serverTime)
        clockOffset = Date.parse(next.serverTime) - Date.now();
      renderQr(next.qr);
    } else if (next?.revision !== state?.revision) applyState(next);
  } catch (error) {
    setConnected(false);
    message(error.message, true);
  } finally {
    polling = false;
  }
}, 3000);
setInterval(updateQrClock, 1000);
lock(true);
await reload();
lock(false);
