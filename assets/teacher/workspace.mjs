const valid = (value) => ["", "P", "A"].includes(value);
export const normalizeSearch = (value) =>
  String(value)
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .replace(/đ/g, "d")
    .trim();
export function matchesStudent(student, query) {
  const text = normalizeSearch(
    `${student.roll} ${student.name} ${student.email} ${student.memberCode}`,
  );
  return normalizeSearch(query)
    .split(/\s+/)
    .every((word) => text.includes(word));
}
export function rosterMarks(students, marks = {}) {
  return Object.fromEntries(
    students.map((student) => [
      student.roll,
      valid(marks[student.roll]) ? marks[student.roll] : "",
    ]),
  );
}
export function changedCount(base, marks) {
  return Object.keys(marks).filter((roll) => marks[roll] !== base[roll]).length;
}
export function mergeDraft(base, local, remote) {
  const conflicts = [];
  const marks = Object.fromEntries(
    Object.keys(remote).map((roll) => {
      const edited = Object.hasOwn(local, roll) && local[roll] !== base[roll];
      if (edited && remote[roll] !== base[roll] && remote[roll] !== local[roll])
        conflicts.push(roll);
      return [roll, edited ? local[roll] : remote[roll]];
    }),
  );
  return { marks, conflicts };
}
export function defaultSession(sessions, today, previous = "") {
  if (sessions.some((session) => session.id === previous)) return previous;
  const sorted = [...sessions].sort(
    (a, b) => a.date.localeCompare(b.date) || a.slot - b.slot,
  );
  return (
    sorted.find((s) => s.state === "open")?.id ??
    sorted.find((s) => s.date === today)?.id ??
    sorted.filter((s) => s.date < today).at(-1)?.id ??
    sorted[0]?.id ??
    ""
  );
}
export class DraftStore {
  constructor(storage, key) {
    this.storage = storage;
    this.key = key;
    this.entries = Object.create(null);
    this.persistent = true;
    try {
      const saved = JSON.parse(storage.getItem(key) || "{}");
      if (saved && typeof saved === "object" && !Array.isArray(saved)) {
        for (const [id, entry] of Object.entries(saved)) {
          if (
            id.length < 200 &&
            entry &&
            Number.isInteger(entry.revision) &&
            entry.base &&
            entry.marks &&
            !Array.isArray(entry.base) &&
            !Array.isArray(entry.marks) &&
            Object.keys(entry.marks).length <= 1000 &&
            Object.values(entry.marks).every(valid) &&
            Object.values(entry.base).every(valid)
          )
            this.entries[id] = {
              ...entry,
              conflicts: Array.isArray(entry.conflicts)
                ? entry.conflicts.filter(
                    (roll) =>
                      typeof roll === "string" &&
                      Object.hasOwn(entry.marks, roll),
                  )
                : [],
            };
        }
      }
    } catch {
      this.persistent = false;
    }
  }
  get(id) {
    return Object.hasOwn(this.entries, id) ? this.entries[id] : null;
  }
  put(id, base, marks, revision, conflicts = []) {
    if (changedCount(base, marks))
      this.entries[id] = {
        base: { ...base },
        marks: { ...marks },
        revision,
        conflicts,
      };
    else delete this.entries[id];
    this.flush();
  }
  remove(id) {
    delete this.entries[id];
    this.flush();
  }
  flush() {
    try {
      this.storage.setItem(this.key, JSON.stringify(this.entries));
    } catch {
      this.persistent = false;
    }
  }
}
