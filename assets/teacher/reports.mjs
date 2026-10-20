export function buildReport(state, group) {
  const sessions = state.sessions.filter(
    (s) => s.groupId === group.id && s.state !== "cancelled",
  );
  const total = group.requiredTotal ?? group.plannedTotal ?? null;
  return group.students.map((student) => {
    const marks = sessions.map((s) => state.records[s.id]?.marks[student.roll]);
    const present =
      student.present ?? marks.filter((mark) => mark === "P").length;
    const absent =
      student.absent ?? marks.filter((mark) => mark === "A").length;
    const percent =
      student.absencePercent ?? (total ? (absent * 100) / total : null);
    return {
      ...student,
      present,
      absent,
      total,
      percent,
      warning:
        group.absenceWarningPercent != null &&
        percent != null &&
        percent >= group.absenceWarningPercent,
    };
  });
}
const cell = (value) => {
  let text = String(value ?? "");
  if (/^[=+\-@\t\r]/.test(text)) text = "'" + text;
  return '"' + text.replaceAll('"', '""') + '"';
};
export function reportCsv(group, rows) {
  const data = [
    [
      "Mon",
      "Lop",
      "MSSV",
      "HoTen",
      "CoMat",
      "Vang",
      "TongPhaiHoc",
      "VangPhanTram",
      "NguongCanhBao",
      "CanhBao",
    ],
    ...rows.map((row) => [
      group.subject,
      group.classCode,
      row.roll,
      row.name,
      row.present,
      row.absent,
      row.total,
      row.percent == null ? "" : row.percent.toFixed(1),
      group.absenceWarningPercent,
      row.warning ? "Dat nguong" : "",
    ]),
  ];
  return (
    "\uFEFF" + data.map((row) => row.map(cell).join(",")).join("\r\n") + "\r\n"
  );
}
export function downloadText(text, name, type = "text/csv;charset=utf-8") {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const link = document.createElement("a");
  link.href = url;
  link.download = name;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
export function vietnamTime(value) {
  if (!value) return "Chưa có lịch sử";
  const date = new Date(value);
  return Number.isFinite(date.getTime())
    ? date.toLocaleString("vi-VN", { timeZone: "Asia/Ho_Chi_Minh" })
    : "Chưa có lịch sử";
}
