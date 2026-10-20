const local = ["http://127.0.0.1:8990", "http://localhost:8990"].includes(
  location.origin,
);
let connection;
const storageKey = "fap-mock-connection";
export function getConnection() {
  if (connection) return connection;
  const fragment = new URLSearchParams(location.hash.slice(1));
  const fresh = fragment.has("api") || fragment.has("key");
  if (fresh) history.replaceState(null, "", location.pathname);
  let candidate;
  try {
    candidate = fresh
      ? {
          api: fragment.get("api") || (local ? location.origin : ""),
          key: fragment.get("key"),
        }
      : JSON.parse(sessionStorage.getItem(storageKey) || "null");
    if (!candidate && local) return null;
    if (
      !candidate ||
      !(
        (local && candidate.api === location.origin) ||
        /^https:\/\/[a-z0-9-]+\.trycloudflare\.com$/.test(candidate.api)
      ) ||
      !/^[A-Za-z0-9_-]{43}$/.test(candidate.key) ||
      (fresh &&
        (fragment.getAll("api").length > 1 ||
          fragment.getAll("key").length !== 1))
    )
      throw Error();
  } catch {
    sessionStorage.removeItem(storageKey);
    throw Error(
      "Chưa kết nối máy GV. Mở Cấu hình → Kết nối web GV trong app Windows và dùng liên kết riêng của giảng viên.",
    );
  }
  connection = candidate;
  try {
    sessionStorage.setItem(storageKey, JSON.stringify(candidate));
  } catch {}
  return connection;
}
async function request(url, body) {
  const link = getConnection();
  const headers =
    body === undefined ? {} : { "Content-Type": "application/json" };
  if (link) headers.Authorization = `Bearer ${link.key}`;
  let response;
  try {
    response = await fetch((link?.api ?? "") + url, {
      method: body === undefined ? "GET" : "POST",
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(15000),
      credentials: "omit",
      referrerPolicy: "no-referrer",
      cache: "no-store",
    });
  } catch {
    throw Error(
      "Mất kết nối máy GV. Bản nháp được giữ; kiểm tra app Windows rồi bấm thử lại.",
    );
  }
  if (!response.ok) {
    let result;
    try {
      result = await response.json();
    } catch {}
    const error = Error(result?.error || "Chưa hoàn tất yêu cầu. Hãy thử lại.");
    error.status = response.status;
    throw error;
  }
  return response;
}
export async function requestApi(url, body) {
  return (await request(url, body)).json();
}
export async function requestFile(url) {
  return (await request(url)).text();
}
export function connectLink(value) {
  const url = new URL(value);
  const params = new URLSearchParams(url.hash.slice(1));
  const candidate = {
    api: params.get("api") || (local ? location.origin : ""),
    key: params.get("key"),
  };
  if (
    url.origin !== location.origin ||
    url.pathname !== "/" ||
    url.search ||
    params.getAll("api").length > 1 ||
    params.getAll("key").length !== 1 ||
    !(
      (local && candidate.api === location.origin) ||
      /^https:\/\/[a-z0-9-]+\.trycloudflare\.com$/.test(candidate.api)
    ) ||
    !/^[A-Za-z0-9_-]{43}$/.test(candidate.key)
  )
    throw Error(
      "Dùng liên kết riêng của giảng viên, đúng domain trang này, do app Windows cung cấp.",
    );
  connection = candidate;
  try {
    sessionStorage.setItem(storageKey, JSON.stringify(candidate));
  } catch {}
  history.replaceState(null, "", location.pathname);
}
