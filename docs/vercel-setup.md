# Đưa trang sinh viên lên Vercel

Áp dụng cho Windows app **v0.3.2 trở lên**. Trang SV dùng địa chỉ production Vercel cố định; Google đăng nhập tại địa chỉ đó. App tự mở Cloudflare Quick Tunnel để tiếp nhận kết quả và lưu JSON trên máy GV. Không cần database hay mua tên miền. Kết nối Cloudflare vẫn là loại thử nghiệm và máy GV cần mở app/có Internet trong lúc nhận điểm danh.

## 1. Đăng nhập Vercel và triển khai

Tạo tài khoản hoặc đăng nhập tại https://vercel.com. Máy làm việc hiện có Node.js/npm.

Mở **PowerShell** và chạy lần lượt:

```powershell
Set-Location 'D:\Projects\FAP-Helper\fap_helper_v1\deploy\student'
npx.cmd vercel login
npx.cmd vercel --prod
```

- Nếu npm hỏi cài Vercel CLI: chọn `y`.
- Làm theo hướng dẫn đăng nhập Vercel trong trình duyệt; không gửi token đăng nhập cho người khác.
- `Set up and deploy ...?`: chọn `Y`.
- Chọn tài khoản/scope cá nhân phù hợp.
- `Link to existing project?`: chọn `N` nếu đây là lần đầu.
- Tên project: ví dụ `fap-helper-fa26` (Vercel sẽ xác định tên miền còn khả dụng).
- Thư mục mã nguồn: giữ `./`.
- Nếu hỏi framework: chọn **Other**. File `vercel.json` đã đặt Output Directory là `public`; không cần build command hoặc biến môi trường.

Chỉ triển khai thư mục `deploy\student`, không triển khai thư mục gốc Flutter. Thư mục này chỉ chứa trang HTML/CSS/JS và cấu hình hosting; không chứa Excel, roster hoặc thông tin Google của GV.

## 2. Lấy địa chỉ cố định

Mở project trên Vercel → **Settings → Domains**. Sao chép domain production, ví dụ:

```text
https://fap-helper-fa26.vercel.app
```

Tên trên chỉ là ví dụ, không phải địa chỉ đã triển khai cho bạn. Không lấy URL preview hoặc URL riêng của một deployment có chuỗi ngẫu nhiên.

Mở địa chỉ đó bằng cửa sổ ẩn danh: phải thấy trang **FAP Helper / Xác nhận có mặt**. Thông báo yêu cầu quét QR là bình thường vì bạn đang mở trang không có mã.

Nếu hiện yêu cầu đăng nhập **Vercel**, kiểm tra **Settings → Deployment Protection** và cho phép truy cập công khai vào domain production dành cho SV. Đây là quyền truy cập trang; bước Google trong luồng điểm danh vẫn được kiểm tra riêng.

## 3. Khai báo Google

Vào Google Cloud → **Google Auth Platform → Clients** → chọn Client ID loại **Web application** đang dùng.

Trong **Authorized JavaScript origins**, thêm đúng địa chỉ production Vercel ở bước 2. Không thêm đường dẫn, fragment QR hoặc dấu `/` cuối; không nhập vào mục Authorized redirect URIs. Bấm **Save**, chờ Google áp dụng cấu hình.

Chế độ Vercel không cần thêm địa chỉ `trycloudflare.com` mới mỗi buổi. Client ID vẫn được nhập tại app GV, không phải cấu hình environment variable trên Vercel.

## 4. Cấu hình desktop app

Mở app v0.3.2 → **Cấu hình** trên sidebar:

- Giữ Client ID và miền email bạn muốn cho phép.
- **Cách kết nối:** chọn **Internet · trang sinh viên trên Vercel**.
- **Địa chỉ production Vercel:** dán địa chỉ ở bước 2.
- Bấm **Lưu cấu hình**.

Mở lớp → chọn buổi → **Mở buổi** → **Điểm danh QR** → chọn mã bí mật nếu cần → **Bắt đầu nhận QR**.

SV quét QR bằng điện thoại, trang mở dưới domain Vercel, đăng nhập Google và gửi. Email đã xác thực vẫn phải khớp danh sách lớp. GV chốt để ngừng nhận và đánh A cho các ô còn trống.

## 5. Khi cập nhật trang sinh viên

Giữ nguyên Vercel project và domain production. Từ thư mục dự án chạy:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool\prepare_vercel.ps1
Set-Location deploy\student
npx.cmd vercel --prod
```

Không tạo project mới mỗi lần cập nhật. Google origins và địa chỉ đã lưu trên app sẽ tiếp tục dùng được khi domain không đổi.

## Cách kết nối

QR mang token và địa chỉ Cloudflare của đợt nhận trong fragment `#…`. Trang Vercel đọc fragment, xóa khỏi thanh địa chỉ và gọi API trên máy GV; chỉ chấp nhận đích HTTPS Quick Tunnel. Backend chỉ cho phép origin đã cấu hình, hỗ trợ CORS cho đúng ba API quét/đăng nhập/gửi. Token, nonce, mã bí mật, xác thực Google và hàng đợi lưu JSON giữ nguyên quy tắc Phase 3.

Tài liệu chính thức: [triển khai bằng CLI](https://vercel.com/docs/projects/deploy-from-cli), [domain production](https://vercel.com/docs/domains/working-with-domains), [cấu hình static](https://vercel.com/docs/project-configuration/vercel-json), [Google origins](https://developers.google.com/identity/gsi/web/guides/get-google-api-clientid).

Việc đăng nhập Vercel, tạo project và triển khai công khai do người dùng thực hiện theo hướng dẫn trên. Gói nguồn chuẩn bị trong workspace chưa tự động trở thành website Vercel.
