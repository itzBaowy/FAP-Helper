# Cải tiến toàn bộ luồng giảng viên và sinh viên

Phạm vi được người dùng xác nhận: toàn bộ luồng GV → SV, làm tất cả các đề xuất đã thảo luận. Giữ Windows là nguồn dữ liệu chuẩn; web GV làm việc với cùng dữ liệu khi kết nối, vẫn giữ chế độ giả lập riêng để thử extension.

## Tiêu chí hoàn thành

- Web GV cảnh báo và giữ bản nháp khi đổi lớp/buổi, tải lại hoặc kết nối gián đoạn. Hiện rõ chưa lưu/đang lưu/đã lưu/lỗi và không ghi đè thay đổi đồng thời.
- Web GV có tìm MSSV/tên/email, lọc P/A/chưa ghi nhận từ số thống kê, chọn buổi hôm nay khi phù hợp, giao diện tập trung vào bảng và thao tác lưu trên màn hình hẹp.
- Kiểm tra kết nối trước buổi, trạng thái online/offline và thử lại. Không báo đã kết nối hay đã lưu khi chưa có bằng chứng từ máy GV.
- SV tải lại trang vẫn tiếp tục lượt quét hợp lệ trong đúng 3 phút từ lần quét đầu. Không lưu Google credential; hết hạn/dừng/chốt phải từ chối. Mã QR vẫn đổi 15 giây và mã cũ không cấp lượt mới.
- Theo dõi rõ lượt quét còn hạn, SV đã xác thực, P đã lưu; không gán danh tính cho lượt chưa xác thực.
- Chốt có xem lại số chưa ghi nhận và xác nhận phạm vi toàn lớp; ghi file lỗi không báo thành công.
- Báo cáo theo SV/lớp, CSV, lịch sử và cảnh báo theo ngưỡng vắng do GV cấu hình. Không tự áp dụng một quy định vắng học chưa được xác nhận.
- Web và Windows nhận thay đổi từ cùng Markbook, ghi qua cùng hàng đợi; yêu cầu cũ bị từ chối/đối chiếu, không âm thầm ghi đè.
- Giữ hợp đồng CSV/extension hiện có, dữ liệu JSON cũ, các điểm P/A và quy tắc sửa sau chốt có lý do.

## Cách thực hiện

1. Khôi phục lượt SV qua sessionStorage chứa mã lượt và địa chỉ API đã kiểm tra; server xác minh lại hạn và trạng thái. Kiểm thử trước/sau đổi QR, tải lại, hết hạn, dừng, gửi lặp và lỗi mạng.
2. Tách MarkbookWorkspace quản lý trạng thái và hàng đợi ghi; QrCollection quản lý vòng đời nhận QR. Giao diện native và HTTP GV sử dụng cùng các module này.
3. HTTP GV dùng khóa ngẫu nhiên riêng, origin cho phép chính xác, không chia sẻ API quản trị với trang SV. Web giữ chế độ mock độc lập nhưng hiện rõ nguồn dữ liệu.
4. Nâng cấp giao diện GV, bản nháp/đối chiếu, báo cáo và chuẩn bị các bản static/assets nhất quán.
5. Chạy kiểm thử nghiệp vụ, HTTP, trình duyệt với dữ liệu giả, responsive và phân tích mã; kiểm tra biên dịch Windows trong khả năng toolchain. Báo riêng những phần chưa triển khai ra Internet.

## Trạng thái ban đầu

Commit nền: `326e152`. Đang có các thay đổi chưa commit về QR 15 giây/lượt quét 3 phút; giữ nguyên và tích hợp. Trước đợt này: 76 kiểm thử Flutter và 17 Node đạt; chưa có .exe mới vì thiếu bộ công cụ C++ Windows. Không tự coi commit/push là deploy website.

## Cách dùng v0.4.0

1. Import Excel vào app Windows hoặc qua web đã kết nối. Trong **Cấu hình**, thiết lập Google Client ID, miền email và kiểu kết nối SV như trước.
2. Vào **Web giảng viên · cùng dữ liệu Windows**, bấm **Kết nối web GV**, sao chép liên kết và mở trong trình duyệt trên cùng máy. Web được phục vụ từ assets kèm app, không cần chạy Node. Nếu muốn dùng từ Internet, triển khai thư mục `deploy/mock-fap`, bật kết nối Internet và nhập origin HTTPS của website đó.
3. Chọn lớp/buổi, **Mở buổi → Bắt đầu nhận QR**. Theo dõi lượt quét, số SV đã xác thực và P đã lưu. Danh tính chỉ xuất hiện sau xác thực; số lượt quét có thể nhiều hơn số người. Tắt hiển thị danh sách khi trình chiếu.
4. SV quét QR hiện hành, đăng nhập và xác nhận trong 3 phút từ lần quét được server chấp nhận. F5 giữ nguyên lượt/hạn. QR cũ sau 15 giây không cấp lượt mới. Dừng/chốt từ chối lượt còn hạn ngay.
5. Giảng viên có thể sửa P/A trên Windows hoặc web. Web nhận cập nhật khoảng mỗi 3 giây khi tab đang hiển thị; native nhận thông báo trực tiếp sau khi ghi file thành công. Khi xung đột, đối chiếu rồi chọn kết quả trước khi lưu. Bản nháp giữ trong tab; mất mạng không tự ghi vào máy GV.
6. **Chốt danh sách** áp dụng toàn lớp và chuyển ô trống thành A, kể cả dòng đang ẩn. Sau chốt, sửa cần lý do. Xuất CSV buổi theo hợp đồng 17 cột hiện có, hoặc báo cáo tổng hợp cả lớp. Cấu hình tổng số buổi/ngưỡng cảnh báo nếu cần; bỏ trống ngưỡng để tắt cảnh báo.

Import/reset bị chặn khi QR đang nhận hoặc đang thay đổi kết nối, tránh thay danh sách giữa lúc xác thực. Ngắt web không xóa P/A và không tự chốt buổi. Khóa liên kết GV thay khi kết nối lại; không gửi liên kết này cho SV. Cổng 8990 dùng cho Windows hoặc mock Node tại một thời điểm.

## Module và tương thích

- `MarkbookWorkspace` giữ Markbook hiện tại, revision và hàng đợi ghi bền vững. Native, HTTP GV và QR cùng dùng đối tượng này. Chỉ công bố trạng thái mới sau khi lưu thành công; snapshot/revision cũ bị từ chối.
- `QrCollection` quản lý một đợt QR dùng chung native/web, server SV và tunnel. API SV tách khỏi API GV có khóa. Khi dừng/chốt, server SV giữ tối đa 3 phút chỉ để trả lỗi đã dừng cho lượt cũ.
- `TeacherWorkspaceHost` xác thực khóa và exact origin, trả trạng thái theo revision, ghi/chốt/xuất CSV và lịch sử phân trang. Đọc trạng thái không đổi không chiếu lại toàn bộ roster/lịch sử. UI nằm trong `mock-fap/public`; script `tool/prepare_teacher.ps1` đồng bộ với `assets/teacher` và `deploy/mock-fap/public`.
- `workspace.mjs` quản lý đối chiếu ba phía và bản nháp; `reports.mjs` tính báo cáo/xuất CSV. sessionStorage giữ bản nháp và lựa chọn của tab, có cảnh báo khi trình duyệt không cho lưu; không coi đây là nơi lưu kết quả chính.
- JSON schema 2 cũ tiếp tục đọc được. `absenceWarningPercent` là trường tùy chọn, mặc định không đặt quy định. CSV 17 cột và extension v0.4.2 giữ tương thích. Mock Node vẫn dùng file riêng `FAPHelper-Mock/mock-fa26.json`, hiện rõ nguồn riêng.

## Kiểm chứng ngày 21/10/2026

- **86 kiểm thử Flutter đạt**: nghiệp vụ, HTTP thật, ghi lỗi, hàng đợi, QR trùng/hết hạn/resume, đối chiếu revision, lịch sử, cấu hình và giao diện native. Bảng native đang mở nhận được thay đổi từ workspace dùng chung. Hộp thoại native không hiển thị/dừng/chốt nhầm đợt QR đã được chuyển trên web. `flutter analyze` không có lỗi.
- **24 kiểm thử Node đạt**: CSV, importer Excel, bản nháp/đối chiếu, báo cáo, SV tải lại/hết hạn/gửi trùng và tính đồng nhất của assets.
- **10 tình huống Chrome GV → SV đạt**: khóa GV; bản nháp qua đổi buổi/F5; tìm kiếm/lọc; lưu bền vững; QR và resume trước/sau xác thực; xung đột; mất mạng/kết nối lại; chốt dòng ẩn/thu hồi lượt/CSV; báo cáo/ngưỡng/bản nháp cấu hình; màn hình 390px không tràn trang. Chạy qua HTTP Dart và file thật trong thư mục tạm, dùng 3 SV `example.com` và Google verifier/nút đăng nhập giả riêng cho test.
- Extension MV3 thật đạt **13 kiểm tra localhost và 14 kiểm tra cấu hình Vercel mô phỏng**: cấp activeTab, popup, scripting, điền-submit, lưu/đọc lại và lỗi server. Không chứng minh triển khai Vercel thật.
- Dart AOT và assets Windows release biên dịch thành công. `flutter build windows --release` vẫn báo thiếu Visual Studio toolchain; không có `.exe` v0.4.0. Không sử dụng binary cũ làm bằng chứng bản mới.

Bằng chứng local (không đưa dữ liệu thật/khóa vào Git): `build/end-to-end-all-tests.log`, `build/end-to-end-analysis.log`, `build/end-to-end-windows-build.log`, `build/previews/end-to-end-browser.json`, `build/previews/phase4-browser.json`, `build/previews/phase4-vercel-browser.json`. Ảnh: [web GV có QR](../build/previews/e2e-teacher-qr.png), [web GV 390px](../build/previews/e2e-teacher-mobile.png), [biên nhận SV](../build/previews/e2e-student-success.png). QR/khóa trong fixture đã dừng sau kiểm tra.

## Chạy lại

```powershell
& .\tool\prepare_teacher.ps1
& .\tool\prepare_vercel.ps1
& 'C:\Flutter\flutter\bin\flutter.bat' analyze
& 'C:\Flutter\flutter\bin\flutter.bat' test
node --test test/*.test.mjs
```

Để kiểm tra trình duyệt, cài Playwright vào thư mục công cụ riêng và đặt `FAP_PLAYWRIGHT_MODULE` tới package đó. Chạy `flutter test tool/end_to_end_host_test.dart` trong một terminal, đợi fixture sẵn sàng; ở terminal khác chạy `node tool/end_to_end_browser_smoke.mjs`. Script tự dừng fixture sau khi kiểm tra. Chạy `node tool/phase4_browser_smoke.mjs` và thêm `--vercel` để kiểm tra extension; có thể đặt `FAP_BROWSER_CHANNEL=chrome` nếu dùng Chrome đã cài.

## Giới hạn bàn giao

Mã nguồn và assets mới đã được kiểm thử; chưa nghiệm thu Google thật, chưa triển khai lại web GV/SV production và chưa tạo binary native mới. Quick Tunnel phụ thuộc app/mạng của máy GV, không có cam kết uptime. Bản nháp trong tab không thay thế sao lưu dữ liệu. QR/xác thực email chưa chứng minh có mặt vật lý trong lớp.
