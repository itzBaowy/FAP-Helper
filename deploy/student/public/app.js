"use strict";
(() => {
  const $ = (id) => document.getElementById(id);
  let scan;
  let timer;
  let completed = false;
  let signingIn = false;
  let submitting = false;
  let expired = false;
  let starting = false;
  let pendingToken = "";
  let deadline;
  const storageKey = "fap-student-scan-v1";
  let apiOrigin = location.origin;
  function forgetScan() {
    try {
      sessionStorage.removeItem(storageKey);
    } catch {}
  }
  function storedScan() {
    try {
      const value = JSON.parse(sessionStorage.getItem(storageKey) || "null");
      if (
        !value ||
        !/^[A-Za-z0-9_-]{43}$/.test(value.ticket) ||
        !(
          value.api === location.origin ||
          /^https:\/\/[a-z0-9-]+\.trycloudflare\.com$/.test(value.api)
        )
      )
        return null;
      return value;
    } catch {
      return null;
    }
  }
  function rememberScan() {
    // Keep only a short-lived bearer ticket. Never store Google credentials or roster data.
    try {
      sessionStorage.setItem(
        storageKey,
        JSON.stringify({ ticket: scan.ticket, api: apiOrigin }),
      );
    } catch {}
  }
  const message = (text, error = false) => {
    $("message").textContent = text;
    $("message").className = error ? "error" : "";
  };
  async function api(path, data) {
    const response = await fetch(apiOrigin + path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(data),
      credentials: "omit",
      cache: "no-store",
      signal: AbortSignal.timeout(20000),
    });
    const result = await response.json();
    if (!response.ok) {
      const error = new Error(
        result.error || "Yêu cầu chưa hoàn tất. Hãy thử lại.",
      );
      error.status = response.status;
      throw error;
    }
    return result;
  }
  function failure(error) {
    message(
      error.name === "TimeoutError" || error instanceof TypeError
        ? "Mất kết nối hoặc chưa nhận được phản hồi. Hãy thử lại; hệ thống không ghi trùng điểm danh."
        : error.message,
      true,
    );
    $("retry").hidden =
      error.status === 410 || (!storedScan() && !pendingToken);
    if (error.status === 410) {
      expired = true;
      pendingToken = "";
      forgetScan();
      $("login").hidden = true;
      $("attendance").hidden = true;
      clearInterval(timer);
      $("expiry").textContent =
        "Quét QR mới nếu giảng viên vẫn đang nhận điểm danh.";
    }
  }
  function updateExpiry() {
    if (!scan || completed || expired) return;
    const seconds = Math.max(0, Math.ceil((deadline - Date.now()) / 1000));
    $("expiry").textContent =
      `Phiên của bạn còn ${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")} để hoàn tất điểm danh.`;
    if (seconds === 0)
      failure(
        Object.assign(new Error("Lượt quét đã hết 3 phút. Hãy quét QR mới."), {
          status: 410,
        }),
      );
  }
  function showIdentity(identity) {
    $("identity").textContent =
      `${identity.fullName} · ${identity.rollNumber}\n${identity.email}`;
    $("login").hidden = true;
    $("attendance").hidden = false;
    $("secret-field").hidden = !scan.requiresSecret;
    $("secret").required = scan.requiresSecret;
    message("Kiểm tra thông tin rồi bấm xác nhận có mặt.");
  }
  function showSuccess(duplicate) {
    completed = true;
    clearInterval(timer);
    $("success-title").textContent = duplicate
      ? "Bạn đã điểm danh trước đó"
      : "Đã ghi nhận có mặt";
    $("success-detail").textContent = duplicate
      ? "Kết quả P đã được lưu cho buổi học này. Lượt gửi lại không tạo thêm bản ghi. Bạn có thể đóng trang."
      : "Kết quả P đã được lưu cho buổi học này. Bạn có thể đóng trang.";
    $("login").hidden = true;
    $("attendance").hidden = true;
    $("retry").hidden = true;
    $("success").hidden = false;
    $("expiry").textContent = "";
    message("");
  }
  async function googleCredential(result) {
    updateExpiry();
    if (!scan || signingIn || completed || expired) return;
    signingIn = true;
    message("Đang xác thực tài khoản Google…");
    try {
      const identity = await api("/api/login", {
        ticket: scan.ticket,
        credential: result.credential,
      });
      updateExpiry();
      if (expired) return;
      showIdentity(identity);
    } catch (error) {
      failure(error);
    } finally {
      signingIn = false;
    }
  }
  $("attendance").addEventListener("submit", async (event) => {
    event.preventDefault();
    if (submitting || completed) return;
    updateExpiry();
    if (!scan || expired) return;
    submitting = true;
    $("submit").disabled = true;
    message("Đang lưu điểm danh…");
    try {
      const result = await api("/api/submit", {
        ticket: scan.ticket,
        secret: $("secret").value.trim(),
      });
      showSuccess(result.duplicate);
    } catch (error) {
      failure(error);
    } finally {
      submitting = false;
      $("submit").disabled = completed;
    }
  });
  async function start() {
    if (starting) return;
    starting = true;
    $("retry").disabled = true;
    $("retry").hidden = true;
    clearInterval(timer);
    try {
      const fragment = location.hash.slice(1);
      let qr = fragment || pendingToken;
      history.replaceState(null, "", location.pathname);
      if (fragment) forgetScan();
      if (fragment.startsWith("token=")) {
        const parameters = new URLSearchParams(fragment);
        qr = parameters.get("token") || "";
        const backend = parameters.get("api") || "";
        // Remote QR destinations are restricted to the teacher's Quick Tunnel.
        if (
          !/^https:\/\/[a-z0-9-]+\.trycloudflare\.com$/.test(backend) ||
          parameters.getAll("api").length !== 1 ||
          parameters.getAll("token").length !== 1
        ) {
          $("lesson").textContent = "Địa chỉ kết nối không hợp lệ.";
          message("Hãy quét QR được tạo từ app giảng viên.", true);
          return;
        }
        apiOrigin = backend;
      }
      const saved = qr ? null : storedScan();
      if (!saved && !/^[A-Za-z0-9_-]{43}$/.test(qr)) {
        $("lesson").textContent =
          "Mở trang bằng mã QR trên màn hình giảng viên.";
        message("Không có mã QR hợp lệ. Hãy quét lại.", true);
        return;
      }
      // Exchange immediately: QR lives 15 s; the scanned ticket allows 3 min for Google login.
      if (saved) {
        apiOrigin = saved.api;
        message("Đang khôi phục lượt quét còn hạn…");
        scan = await api("/api/resume", { ticket: saved.ticket });
      } else {
        pendingToken = qr;
        scan = await api("/api/scan", { token: qr });
      }
      const expires = Date.parse(scan.expiresAt);
      const serverTime = scan.serverTime
        ? Date.parse(scan.serverTime)
        : Date.now();
      if (
        !Number.isFinite(expires) ||
        !Number.isFinite(serverTime) ||
        !/^[A-Za-z0-9_-]{43}$/.test(scan.ticket)
      )
        throw new Error("Không đọc được thời hạn lượt quét. Hãy quét QR mới.");
      deadline = Date.now() + Math.min(180000, expires - serverTime);
      expired = false;
      pendingToken = "";
      rememberScan();
      $("lesson").textContent = `${scan.classLabel} · ${scan.sessionLabel}`;
      if (scan.submitted) {
        showSuccess(true);
        return;
      }
      $("login").hidden = false;
      message(
        saved
          ? "Đã khôi phục lượt quét. Thời hạn vẫn tính từ lần quét đầu."
          : "Đã giữ lượt quét trong 3 phút. Tiếp tục đăng nhập Google; QR đổi không làm mất lượt này.",
      );
      updateExpiry();
      if (expired) return;
      timer = setInterval(updateExpiry, 1000);
      if (scan.identity) {
        showIdentity(scan.identity);
        return;
      }
      const googleDeadline = Date.now() + 15000;
      while (!window.google?.accounts?.id) {
        if (Date.now() > googleDeadline)
          throw new Error(
            "Chưa tải được đăng nhập Google. Kiểm tra Internet rồi bấm thử lại.",
          );
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
      updateExpiry();
      if (expired) return;
      google.accounts.id.initialize({
        client_id: scan.clientId,
        callback: googleCredential,
        nonce: scan.nonce,
        auto_select: false,
      });
      google.accounts.id.renderButton($("google-button"), {
        theme: "outline",
        size: "large",
        text: "signin_with",
        locale: "vi",
        width: Math.min(340, $("login").clientWidth),
      });
    } catch (error) {
      failure(error);
    } finally {
      starting = false;
      $("retry").disabled = false;
    }
  }
  $("retry").addEventListener("click", start);
  start();
})();
