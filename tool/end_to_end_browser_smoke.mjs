import { createRequire } from "node:module";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import assert from "node:assert/strict";
import { parseCsv } from "../extension/csv.mjs";
const require = createRequire(import.meta.url);
const { chromium } = require(
  process.env.FAP_PLAYWRIGHT_MODULE ||
    "../build/browser-tools/node_modules/playwright",
);
const checks = [],
  errors = [];
let browser,
  debugPage,
  injectingOffline = false;
const check = (name) => {
  checks.push(name);
  console.log("PASS " + name);
};
try {
  const host = JSON.parse(await readFile("build/e2e-host.json", "utf8"));
  browser = await chromium.launch({ channel: "chrome", headless: true });
  const teacher = await browser.newContext({
    viewport: { width: 1360, height: 960 },
    acceptDownloads: true,
  });
  const page = await teacher.newPage();
  debugPage = page;
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("console", (entry) => {
    if (entry.type() === "error" && !injectingOffline)
      errors.push(entry.text());
  });
  const api = async (path, body) => {
    const response = await fetch(host.origin + path, {
      method: body ? "POST" : "GET",
      headers: {
        Origin: host.origin,
        Authorization: "Bearer " + host.key,
        ...(body ? { "Content-Type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    const result = await response.json();
    assert.equal(response.status, 200, JSON.stringify(result));
    return result;
  };
  await page.goto(host.link);
  await page.locator("tr[data-roll]").first().waitFor();
  assert.match(await page.locator("#source-label").innerText(), /Windows/);
  check("teacher uses the Windows source through authenticated HTTP");
  await page.locator('tr[data-roll="SE000001"] select').selectOption("P");
  await page
    .locator("#session")
    .selectOption("FA26/PRM393/SE1920/2026-09-10/1");
  await page
    .getByRole("button", { name: "Giữ bản nháp và chuyển", exact: true })
    .click();
  await page
    .locator("#session")
    .selectOption("FA26/PRM393/SE1920/2026-09-07/1");
  assert.equal(
    await page.locator('tr[data-roll="SE000001"] select').inputValue(),
    "P",
  );
  page.once("dialog", (dialog) => dialog.accept());
  await page.reload();
  await page.locator("tr[data-roll]").first().waitFor();
  assert.equal(
    await page.locator('tr[data-roll="SE000001"] select').inputValue(),
    "P",
  );
  check("teacher draft survives session navigation and reload");
  await page.locator("#search").fill("tran binh");
  assert.equal(await page.locator("#students tr:visible").count(), 1);
  await page.locator('[data-filter="P"]').click();
  assert.equal(await page.locator("#students tr:visible").count(), 0);
  await page.locator("#search").fill("");
  await page.locator('[data-filter="all"]').click();
  check(
    "accent-insensitive search and status filters combine without removing roster controls",
  );
  await page.locator('button[type="submit"]').click();
  await page.waitForFunction(() =>
    document.querySelector("#saved").textContent.startsWith("Đã lưu"),
  );
  check("teacher saves only after the shared Windows write succeeds");
  await page.locator("#require-secret").check();
  await page.locator("#start-qr").click();
  await page.locator("#qr-panel").waitFor({ state: "visible" });
  const qr = (await api("/api/state")).qr;
  assert(qr.active);
  assert(qr.svg.startsWith("<svg"));
  const studentContext = await browser.newContext({
    viewport: { width: 390, height: 844 },
  });
  await studentContext.route(
    "https://accounts.google.com/gsi/client",
    (route) =>
      route.fulfill({
        contentType: "text/javascript",
        body: `window.google={accounts:{id:{initialize(o){this.options=o},renderButton(target){const button=document.createElement('button');button.textContent='Google fixture';button.onclick=()=>this.options.callback({credential:'binh@example.com'});target.append(button)}}}};`,
      }),
  );
  const student = await studentContext.newPage();
  student.on("pageerror", (error) => errors.push(error.message));
  await student.goto(qr.url);
  await student.getByText("Google fixture", { exact: true }).waitFor();
  const before = await student.locator("#expiry").innerText();
  await student.reload();
  await student.getByText("Google fixture", { exact: true }).waitFor();
  assert.match(await student.locator("#message").innerText(), /khôi phục/);
  assert.match(before, /2:|3:/);
  await student.getByText("Google fixture", { exact: true }).click();
  await student.locator("#attendance").waitFor({ state: "visible" });
  await student.reload();
  await student.locator("#attendance").waitFor({ state: "visible" });
  await student
    .locator("#secret")
    .fill("000000" === qr.secret ? "111111" : "000000");
  await student.locator("#submit").click();
  await student.waitForFunction(
    () => document.querySelector("#message").className === "error",
  );
  await student.locator("#secret").fill(qr.secret);
  await student.locator("#submit").click();
  await student.locator("#success").waitFor({ state: "visible" });
  await page.waitForFunction(
    () => document.querySelector("#stat-present").textContent === "2",
  );
  check(
    "student resumes the original scan and verified identity, retries a secret and saves P live",
  );
  await page.locator("#show-roster").uncheck();
  assert.equal(await page.locator("#roster-area").isVisible(), false);
  await page.locator("#show-roster").check();
  await mkdir("build/previews", { recursive: true });
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({
    path: "build/previews/e2e-teacher-qr.png",
    fullPage: true,
  });
  await page.locator('tr[data-roll="SE000001"] select').selectOption("");
  let current = await api("/api/state");
  await api("/api/submit", {
    sessionId: current.sessions.find((s) => s.state === "open").id,
    revision: current.revision,
    marks: { SE000001: "A", SE000002: "P", SE000003: "" },
  });
  await page.locator("#conflicts").waitFor({ state: "visible" });
  assert.equal(await page.locator('button[type="submit"]').isEnabled(), false);
  await page.locator("#keep-draft").click();
  await page
    .getByRole("button", { name: "Đã đối chiếu, giữ bản nháp", exact: true })
    .click();
  await page.locator('button[type="submit"]').click();
  await page.waitForFunction(() =>
    document.querySelector("#saved").textContent.startsWith("Đã lưu"),
  );
  check(
    "simultaneous updates require explicit conflict review before the draft can overwrite a result",
  );
  injectingOffline = true;
  await page.route("**/api/state*", (route) => route.abort());
  await page.waitForFunction(() =>
    document
      .querySelector("#connection-status")
      .textContent.includes("Mất kết nối"),
  );
  await page.locator('tr[data-roll="SE000003"] select').selectOption("P");
  await page.unroute("**/api/state*");
  await page.locator("#retry").click();
  await page.waitForFunction(() =>
    document
      .querySelector("#connection-status")
      .textContent.startsWith("Đã kết nối"),
  );
  injectingOffline = false;
  assert.equal(
    await page.locator('tr[data-roll="SE000003"] select').inputValue(),
    "P",
  );
  await page.locator("#discard").click();
  await page
    .getByRole("button", { name: "Bỏ thay đổi", exact: true })
    .last()
    .click();
  check(
    "offline edits remain in a draft and reconnect never silently saves or discards them",
  );
  current = await api("/api/state");
  const pending = await studentContext.newPage();
  await pending.goto(current.qr.url);
  await pending.getByText("Google fixture", { exact: true }).waitFor();
  await page.locator('[data-filter="P"]').click();
  await page.locator("#close-session").click();
  await page
    .getByRole("button", { name: "Xác nhận chốt", exact: true })
    .click();
  await page.waitForFunction(
    () => document.querySelector("#session-state").textContent === "Đã chốt",
  );
  await pending.getByText("Google fixture", { exact: true }).click();
  await pending.waitForFunction(
    () => document.querySelector("#message").className === "error",
  );
  assert.match(await pending.locator("#message").innerText(), /dừng|chốt/);
  const downloadPromise = page.waitForEvent("download");
  await page.locator("#export-session").click();
  const download = await downloadPromise;
  await download.saveAs("build/previews/e2e-attendance.csv");
  const csv = parseCsv(
    await readFile("build/previews/e2e-attendance.csv", "utf8"),
  );
  assert.deepEqual(
    csv[0].students.map((s) => s.status),
    ["A", "P", "A"],
  );
  check(
    "closing applies to hidden students, revokes pending scans and exports the existing CSV contract",
  );
  await page
    .locator("#report-panel")
    .evaluate((element) => (element.open = true));
  await page.locator("#planned-total").fill("10");
  await page.locator("#warning-threshold").fill("10");
  // A fresh server revision must not replace policy fields being edited.
  current = await api("/api/state");
  await api("/api/action", {
    action: "set-warning",
    groupId: "PRM393/SE1920",
    value: 20,
    revision: current.revision,
  });
  await page.waitForFunction(
    (revision) =>
      Number(document.querySelector("#attendance-form").dataset.revision) >
      revision,
    current.revision,
  );
  await page.locator("#retry").click();
  await page.waitForFunction(
    () => document.querySelector("#retry").disabled === false,
  );
  assert.equal(await page.locator("#planned-total").inputValue(), "10");
  assert.equal(await page.locator("#warning-threshold").inputValue(), "10");
  await page.locator("#save-policy").click();
  await page.waitForFunction(() =>
    document.querySelector("#message").textContent.includes("Đã lưu cấu hình"),
  );
  assert.equal(await page.locator("#report-students tr.warning").count(), 2);
  check(
    "class reports use the saved denominator and the teacher-configured absence threshold",
  );
  await page.setViewportSize({ width: 390, height: 844 });
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({
    path: "build/previews/e2e-teacher-mobile.png",
    fullPage: true,
  });
  assert(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth + 1,
    ),
  );
  await student.screenshot({
    path: "build/previews/e2e-student-success.png",
    fullPage: true,
  });
  assert.deepEqual(errors, []);
  check("teacher at 390px and student workflow render without page errors");
  await writeFile(
    "build/previews/end-to-end-browser.json",
    JSON.stringify(
      {
        checks,
        errors,
        identity: "fixture verifier and Google browser stub",
        data: "synthetic",
        remoteDeployment: false,
      },
      null,
      2,
    ),
  );
} catch (error) {
  console.error(
    JSON.stringify({
      errors,
      message: await debugPage
        ?.locator("#message")
        .innerText()
        .catch(() => null),
    }),
  );
  if (debugPage) {
    await mkdir("build/previews", { recursive: true });
    await debugPage
      .screenshot({ path: "build/previews/e2e-failure.png", fullPage: true })
      .catch(() => {});
  }
  throw error;
} finally {
  await browser?.close();
  await writeFile("build/e2e-stop", "stop");
}
