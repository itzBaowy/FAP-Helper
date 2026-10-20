import { test } from "node:test";
import assert from "node:assert/strict";
import {
  DraftStore,
  mergeDraft,
  defaultSession,
  matchesStudent,
} from "../mock-fap/public/workspace.mjs";
import { buildReport, reportCsv } from "../mock-fap/public/reports.mjs";
import { readFile } from "node:fs/promises";

test("draft survives reload, merges independent updates and identifies conflicting students", () => {
  const memory = new Map(),
    storage = {
      getItem: (key) => memory.get(key),
      setItem: (key, value) => memory.set(key, value),
    };
  const first = new DraftStore(storage, "scope");
  first.put("session", { A: "", B: "", C: "" }, { A: "P", B: "A", C: "" }, 3);
  const restored = new DraftStore(storage, "scope").get("session");
  const merged = mergeDraft(restored.base, restored.marks, {
    A: "A",
    B: "",
    C: "P",
  });
  assert.deepEqual(merged, {
    marks: { A: "P", B: "A", C: "P" },
    conflicts: ["A"],
  });
  first.remove("session");
  assert.equal(new DraftStore(storage, "scope").get("session"), null);
});
test("default session prefers an open lesson then today, preserves an explicit selection", () => {
  const sessions = [
    { id: "old", date: "2026-09-07", slot: 1, state: "closed" },
    { id: "today", date: "2026-10-21", slot: 2, state: "planned" },
  ];
  assert.equal(defaultSession(sessions, "2026-10-21"), "today");
  assert.equal(defaultSession(sessions, "2026-10-21", "old"), "old");
  assert.equal(
    defaultSession(
      [...sessions, { id: "open", date: "2026-10-20", slot: 1, state: "open" }],
      "2026-10-21",
    ),
    "open",
  );
  assert.equal(
    matchesStudent(
      {
        roll: "SE000001",
        name: "Nguyễn Đặng An",
        email: "an@example.com",
        memberCode: "an",
      },
      "nguyen dang",
    ),
    true,
  );
});
test("reports use required lessons and configured warning; CSV prevents formula injection", () => {
  const group = {
    id: "PRM393/SE1920",
    subject: "PRM393",
    classCode: "SE1920",
    requiredTotal: 10,
    absenceWarningPercent: 20,
    students: [{ roll: "A", name: "=SUM(1,2)" }],
  };
  const rows = buildReport(
    {
      sessions: [
        { id: "1", groupId: group.id },
        { id: "2", groupId: group.id },
      ],
      records: { 1: { marks: { A: "A" } }, 2: { marks: { A: "A" } } },
    },
    group,
  );
  assert.equal(rows[0].percent, 20);
  assert.equal(rows[0].warning, true);
  assert.match(reportCsv(group, rows), /"'=SUM\(1,2\)"/);
  assert.equal(
    buildReport(
      { sessions: [], records: {} },
      { ...group, requiredTotal: null },
    )[0].percent,
    null,
  );
});
test("all teacher runtime and deploy assets are identical to their canonical source", async () => {
  for (const file of [
    "index.html",
    "app.mjs",
    "connection.mjs",
    "xlsx-importer.mjs",
    "style.css",
    "workspace.mjs",
    "reports.mjs",
  ]) {
    const source = await readFile(
      new URL("../mock-fap/public/" + file, import.meta.url),
      "utf8",
    );
    for (const directory of ["assets/teacher", "deploy/mock-fap/public"])
      assert.equal(
        await readFile(
          new URL("../" + directory + "/" + file, import.meta.url),
          "utf8",
        ),
        source,
      );
  }
});
