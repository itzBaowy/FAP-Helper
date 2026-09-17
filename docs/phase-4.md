# Phase 4 — Trang GV giả lập và Chrome extension

Phiên bản extension **0.4.2**, dùng cùng desktop **0.3.3**. Phase này hoàn tất luồng **desktop → CSV → extension → trang GV giả lập → lưu JSON**. Không cần tài khoản giảng viên của trường.

**v0.4.2 — Vercel:** trang GV có thể dùng domain Vercel cố định, kết nối HTTPS có khóa tới máy GV để lưu JSON; extension có cấu hình domain được phép. Xem [hướng dẫn Vercel cho trang GV](vercel-mock-setup.md).

**Giao diện v0.4.1:** trang GV có thẻ tổng số SV/P/A/chưa ghi nhận cập nhật theo ô điểm danh, avatar chữ cái và bảng có tiêu đề cố định khi cuộn. Extension có phần chọn CSV riêng, các bước chuyển điểm danh, bản xem trước P/A và nút submit luôn ở cuối popup. Bố cục trang thích ứng màn hình nhỏ. Nếu đã cài extension, vào `chrome://extensions` bấm **Reload / Tải lại** ở FAP Helper; tải lại trang giả lập để nhận giao diện mới.

## Chạy thử trên máy này

1. Mở PowerShell trong thư mục dự án, chạy:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File mock-fap/start.ps1
   ```

   Giữ cửa sổ này khi thử; `Ctrl+C` để dừng. Cần Node.js 22 trở lên, máy phát triển hiện có Node.js 22.19.0. Nếu cổng 8990 đang được dùng, dừng bản giả lập đang chạy trước khi mở lại.

2. Mở Chrome tại **http://127.0.0.1:8990**. Bấm **Nhập dữ liệu**, chọn `mock-fap/demo/FA26-demo.json`. Đây là dữ liệu giả gồm 3 sinh viên, 2 buổi; chưa có P/A trên trang.
3. Vào `chrome://extensions`, bật **Developer mode / Chế độ dành cho nhà phát triển**, chọn **Load unpacked / Tải tiện ích đã giải nén**, chọn thư mục `extension` (thư mục chứa `manifest.json`). Ghim **FAP Helper — Điểm danh giả lập** lên thanh công cụ.
4. Trên trang giả lập chọn **PRM393 · SE1920**, buổi **2026-09-07 · Slot 1**.
5. Bấm biểu tượng extension → chọn `mock-fap/demo/FA26-demo.csv` → chọn đúng buổi → **Đối chiếu với tab hiện tại**. Bản xem trước sẽ hiển thị **3 SV: 2 P, 1 A**.
6. Bấm **Điền P/A và submit**. Extension tự điền, kích hoạt submit của trang và chờ xác nhận lưu. Trang sẽ có SE000001 = P, SE000002 = A, SE000003 = P. Tải lại trang để kiểm tra kết quả vẫn còn.

Nếu dùng bản ZIP, giải nén toàn bộ rồi chạy các bước trên từ thư mục đã giải nén. Bản ZIP Phase 4 chứa trang giả lập, extension, dữ liệu mẫu và hướng dẫn; desktop vẫn dùng bản Windows v0.3.3 hiện có.

## Dùng với dữ liệu desktop

1. Điểm danh và **chốt buổi** trong desktop. Xuất CSV của buổi hoặc tất cả buổi đã chốt trong lớp.
2. Trên trang giả lập nhập `%APPDATA%\FAPHelper\FA26.json`. Có thể dán đường dẫn này vào hộp thoại chọn file. Trang chỉ lấy danh sách lớp, sinh viên và các buổi đã lưu; không lấy P/A từ JSON desktop.
3. Chọn lớp/buổi trên trang, dùng extension đọc CSV vừa xuất, đối chiếu rồi submit.
4. Khi desktop có buổi mới, nhập lại FA26.json để cập nhật trang. Kết quả đã submit được giữ lại. Nếu import sẽ xóa buổi đã submit hoặc thay đổi tập MSSV của buổi đó, trang chặn import để tránh làm mất kết quả.

Mỗi lần thao tác chuyển **một buổi**. CSV nhiều buổi có danh sách chọn; không tự chuyển buổi khác. Đóng popup sẽ bỏ CSV và bản xem trước trong bộ nhớ; mở lại cần chọn CSV lại. CSV được đọc trên máy, không gửi tới dịch vụ bên ngoài.

## Quy tắc đối chiếu và lưu

- Khóa buổi: `FA26/MãMôn/MãLớp/YYYY-MM-DD/Slot`; đối chiếu sinh viên bằng MSSV, không bằng thứ tự dòng hoặc họ tên.
- CSV phải đúng 17 cột của desktop, schema 1, kỳ FA26, ngày/slot/giờ thống nhất và trạng thái chỉ P/A. Hỗ trợ UTF-8 BOM, tiếng Việt, dấu phẩy, xuống dòng và nháy kép trong trường. Giới hạn file CSV 5 MB.
- Thiếu/thừa/trùng MSSV, sai buổi, ô bị khóa hoặc trang đã đổi phiên bản dữ liệu sẽ chặn thao tác. Kiểm tra toàn bộ danh sách trước khi điền.
- P/A đã có sẽ được cập nhật theo CSV khi giảng viên chủ động bấm **Điền P/A và submit**. Bản xem trước cho biết số ô thay đổi.
- Extension chỉ báo thành công sau khi trang nhận xác nhận lưu từ server. Nếu lỗi mạng/ghi file/hết thời gian chờ, kiểm tra trạng thái trên trang trước khi thử lại.
- Server kiểm tra lại buổi, tập MSSV và phiên bản dữ liệu; ghi file tạm, flush và đổi tên trước khi trả thành công. Các yêu cầu ghi được xử lý lần lượt. Submit lại cùng kết quả không tạo thay đổi mới.

## Lưu trữ và phạm vi

Trang chạy cục bộ tại `127.0.0.1:8990`, lưu `%APPDATA%\FAPHelper-Mock\mock-fa26.json`, giữ bản sao `.bak` trước lần ghi. Không dùng database, localStorage hoặc IndexedDB. Không ghi vào hồ sơ desktop. Có thể đặt `FAP_MOCK_DATA_DIR` để dùng thư mục thử nghiệm riêng. Nếu file giả lập bị hỏng, server báo lỗi và không tự ghi đè; dừng server và kiểm tra file/bản sao `.bak`.

Trang được ghi rõ là giả lập; giao diện mô phỏng nghiệp vụ điểm danh, chưa xác nhận giống cấu trúc HTML của FAP thật. Extension chạy trên localhost hoặc domain Vercel đã cấu hình, không thao tác FAP của trường. Khi có quyền truy cập trang GV thật hoặc mẫu HTML phù hợp, cần viết adapter và kiểm thử riêng trước khi sử dụng thật.

Extension dùng Manifest V3 với `activeTab`, `scripting` và `storage` (chỉ lưu domain cấu hình), không xin quyền đọc mọi website. Tham khảo [quyền activeTab của Chrome](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab) và [API scripting](https://developer.chrome.com/docs/extensions/reference/api/scripting).

## Nghiệm thu

- Bộ dữ liệu mẫu được sinh bằng `AttendanceCsv` thật của desktop: `dart tool/prepare_phase4_demo.dart`.
- `node --test test/phase4.test.mjs`: 6 nhóm kiểm thử parser CSV, đối chiếu, import, lưu/khởi động lại, lỗi ghi file và xác thực kết nối Vercel.
- `node tool/phase4_browser_smoke.mjs`: 13 kiểm tra trình duyệt, gồm sai buổi, thiếu/sai MSSV, đảo thứ tự dòng, bản xem trước cũ, điền-submit, chỉ lưu buổi đã chọn, tải lại, bộ đếm P/A, bố cục 800/390 px, submit lặp và lỗi server. Server thử nghiệm dùng cổng riêng và ánh xạ request trong trình duyệt test để tránh ảnh hưởng trang người dùng đang chạy ở cổng 8990.
- Kiểm thử trình duyệt cài extension MV3 thật vào Chrome for Testing, cấp `activeTab` qua browser action và chạy trang popup của extension trong tab để tự động hóa; không giả lập `chrome.scripting` hoặc thêm host permission. Công cụ test riêng cần Playwright tại `build/browser-tools` và Chromium; người dùng app không cần các công cụ test này.

Ảnh kết quả giả lập: `build/previews/phase4_mock_saved.png`; ảnh giao diện extension: `build/previews/phase4_extension_preview.png`; báo cáo: `build/previews/phase4-browser.json`. Toàn bộ kiểm thử dùng sinh viên giả.
