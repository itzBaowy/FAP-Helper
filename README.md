# FAP Helper — Phase 4

Ứng dụng Flutter dành cho giảng viên trên Windows, quản lý nhiều môn/lớp trong kỳ **FA26 (FALL 2026)**. Dữ liệu lưu bằng file JSON; không dùng database.

## Đã triển khai

- Chọn file `.xlsx` bằng hộp thoại Windows, đọc nhiều sheet ở luồng nền.
- Kiểm tra dữ liệu và xem trước danh sách từng lớp trước khi xác nhận lưu.
- Tổng quan số lớp học phần, môn, sinh viên duy nhất và lượt đăng ký học.
- Tìm kiếm mã môn/lớp, lọc môn, xem và tìm kiếm danh sách sinh viên.
- Lịch hôm nay, xem lịch theo ngày, lịch tuần và highlight lớp đang trong giờ học.
- Lưu/đọc lại JSON, giữ bản sao lần lưu trước và phục hồi khi file chính hỏng.

Phase 2 bổ sung bảng điểm danh theo buổi, P/A thủ công, chốt, sửa có lý do/lịch sử, cấu hình tổng số buổi, nghỉ/học bù và xuất CSV. Xem [hướng dẫn và nghiệp vụ Phase 2](docs/phase-2.md).

Phase 3 bổ sung QR đổi mỗi 15 giây, mã bí mật tùy chọn, trang sinh viên, xác thực Google và kết nối HTTPS thử nghiệm từ hai mạng khác nhau. Email phải thuộc danh sách lớp và miền cho phép (`gmail.com`, `fpt.edu.vn`). Từ v0.3.1, Client ID, miền email và kết nối được thiết lập tại **Cấu hình** trên sidebar; màn hình QR chỉ giữ tùy chọn mã bí mật cho từng đợt. Xem [cấu hình và hướng dẫn Phase 3](docs/phase-3.md).

Phase 4 bổ sung **trang GV giả lập và Chrome extension**: đọc CSV, đối chiếu đúng buổi/MSSV, xem trước, tự điền P/A và submit. Trang lưu JSON riêng, không cần tài khoản GV của trường. Xem [hướng dẫn chạy thử và nghiệm thu Phase 4](docs/phase-4.md). Desktop hiện dùng v0.3.3; extension v0.4.2 hỗ trợ domain Vercel đã cấu hình. Xem [hướng dẫn Vercel cho trang GV](docs/vercel-mock-setup.md). Adapter FAP thật chưa triển khai.

**v0.3.3 — Reset:** tại Cấu hình, chọn reset một lớp học phần hoặc toàn bộ FA26; nhập RESET để xác nhận. Tự sao lưu trước khi xóa P/A, giữ sinh viên, lịch học, cấu hình và lịch sử.

**v0.3.2 — Vercel:** hỗ trợ trang SV ở domain production cố định, gửi điểm danh qua Cloudflare về máy GV. Mã nguồn triển khai tại `deploy/student`; xem [hướng dẫn Vercel](docs/vercel-setup.md). Chưa tự triển khai lên tài khoản Vercel của người dùng. 65 kiểm thử tự động đạt, phân tích mã không có lỗi.

## Chạy trên Windows

Yêu cầu Flutter tương thích Dart `^3.13.3` và Visual Studio có workload **Desktop development with C++**, bao gồm MSVC, CMake và Windows SDK. Xem [hướng dẫn Windows chính thức của Flutter](https://docs.flutter.dev/platform-integration/windows/setup). Flutter SDK đang có trên máy làm việc là `D:\Flutter\flutter`.

```powershell
& 'D:\Flutter\flutter\bin\flutter.bat' pub get
& 'D:\Flutter\flutter\bin\flutter.bat' run -d windows
```

Build bản release:

```powershell
& 'D:\Flutter\flutter\bin\flutter.bat' build windows --release
```

Khi build thành công, chạy `build\windows\x64\runner\Release\fap_helper_v1.exe`. Khi chuyển sang máy khác phải chuyển **toàn bộ thư mục Release**, gồm DLL và thư mục `data`.

**Kiểm tra Phase 3:** v0.3.0 đã đạt 62/62 kiểm thử và kiểm tra native QR/HTTPS, hết hạn QR, chốt/dừng server với hồ sơ giả; Chrome dùng nút Google giả riêng cho test. Bản cập nhật sidebar v0.3.1 đã đạt 16 kiểm thử liên quan đến cấu hình, sidebar, bảng điểm danh và bố cục; phân tích mã không có lỗi. Người dùng đã nhập Client ID; cần hoàn tất Google Authorized JavaScript origins và nghiệm thu đăng nhập thật. Bản đóng gói: [FAPHelper-Phase3-Windows-x64.zip](build/FAPHelper-Phase3-Windows-x64.zip).

Chạy ngay bản đã build: [fap_helper_v1.exe](build/windows/x64/runner/Release/fap_helper_v1.exe). Máy này đã được import dữ liệu FA26 trong bước kiểm tra. Người dùng chỉ chạy app, không cần cài Flutter hoặc Visual Studio; các công cụ đó dành cho việc build từ mã nguồn. Máy khác cần có Microsoft Visual C++ Runtime phù hợp.

## Import Excel

1. Bấm **Import Excel** và chọn `FA26_Markbook.xlsx` đã chỉnh sửa.
2. Xem số lớp, môn, sinh viên và từng danh sách lớp.
3. Nếu có lỗi, mở tab **Kiểm tra dữ liệu**, sửa dòng được chỉ ra trong Excel rồi import lại. App không lưu một phần file lỗi.
4. Bấm **Xác nhận import**. Nếu đã có dữ liệu, nút hiển thị **Thay dữ liệu FA26 và lưu**. Điểm danh/cấu hình/lịch sử đã có được giữ nguyên khi mã lớp, lịch và tập MSSV không đổi; import thay đổi các thông tin đó của lớp đã điểm danh sẽ bị chặn. Có bản sao trước khi lưu.
5. Chọn **Lớp học phần** để lọc môn/tìm lớp; bấm lớp để điểm danh. Nút **Danh sách SV** trong lớp mở thông tin đầy đủ. Chọn **Lịch tuần** để đối chiếu lịch gốc, hoặc **Tổng quan** để xem lịch theo ngày đã áp dụng nghỉ/học bù.

Tên sheet theo mẫu `11_PRN232_SE1917`: chữ số đầu là cặp ngày, chữ số thứ hai là slot, tiếp theo là mã môn và mã lớp. Mỗi sheet cần các cột `Class`, `RollNumber`, `Email`, `MemberCode`, `FullName`; thứ tự cột có thể thay đổi. Dòng đầu tiên có dữ liệu phải là tiêu đề. Sheet sai tên hoặc thiếu cấu trúc sẽ báo lỗi để người dùng xử lý, không tự bỏ qua.

## Quy tắc lịch

| Tiền tố đầu | Cặp ngày | Buổi đầu từ mốc 07/09/2026 |
|---|---|---|
| 1 | Thứ 2 + Thứ 5 | 07/09/2026 |
| 2 | Thứ 3 + Thứ 6 | 08/09/2026 |
| 3 | Thứ 4 + Thứ 7 | 09/09/2026 |

| Slot | Giờ học |
|---|---|
| 1 | 07:30–09:15 |
| 2 | 09:30–11:45 |
| 3 | 12:30–14:45 |
| 4 | 15:00–17:15 |

Giờ hiện tại dùng GMT+7, cập nhật mỗi 15 giây. Lớp được highlight từ giờ bắt đầu, hết highlight đúng giờ kết thúc. Lịch gốc không có buổi trước mốc đầu kỳ hoặc vào Chủ nhật; có thể thêm học bù vào Chủ nhật. Tổng quan áp dụng nghỉ/học bù và cấu hình số buổi riêng của từng lớp. Khi chưa nhập tổng số buổi, tỷ lệ vắng hiển thị `—`.

## Dữ liệu trên máy

- File chính: `%APPDATA%\FAPHelper\FA26.json`.
- Bản sao trước lần thay dữ liệu: `FA26.json.bak`.
- File `.tmp` được ghi và flush trước khi thay file chính. Nếu ghi thất bại, app không báo import thành công.
- Khi file chính lỗi, app thử đọc bản sao và hiển thị thông báo phục hồi. Lần lưu sau giữ file lỗi thành `.corrupt-<timestamp>`, không ghi file lỗi đè lên bản sao tốt.
- Nếu cả file chính và bản sao đều không đọc được, app ngừng import, hiển thị vị trí dữ liệu để kiểm tra và có nút thử đọc lại. Có thể di chuyển các file lỗi ra chỗ lưu riêng rồi mở lại app để import từ Excel gốc.
- Không tự sửa file Excel nguồn. Không đưa danh sách sinh viên thực tế vào repository hoặc ảnh xem trước.
- Windows runner chỉ cho mở một instance trong phiên Windows để tránh hai cửa sổ đồng thời ghi file.

## Kiểm tra

```powershell
& 'D:\Flutter\flutter\bin\flutter.bat' analyze
& 'D:\Flutter\flutter\bin\flutter.bat' test
& 'D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe' tool/inspect_workbook.dart 'C:\Users\Admin\Downloads\FA26_Markbook.xlsx'
```

Lệnh cuối chỉ in thống kê, lịch và lỗi cấu trúc; không in tên/email/MSSV của sinh viên. Test tự động dùng dữ liệu giả với miền `example.com`.

Để dựng ảnh xem trước từ file local bằng Flutter test renderer:

```powershell
$env:FAP_PREVIEW_WORKBOOK = 'C:\Users\Admin\Downloads\FA26_Markbook.xlsx'
& 'D:\Flutter\flutter\bin\flutter.bat' test tool/render_preview_test.dart
```

Ảnh được lưu trong `build/previews/`; giờ minh họa cố định **15/09/2026 lúc 10:00**. Đây là ảnh từ Flutter test renderer, không phải bằng chứng app native đã build thành công.

Ảnh từ bản Windows release chạy thực tế: [Tổng quan sau khi mở lại](build/previews/native_dashboard.png), [Lịch tuần](build/previews/native_week.png), [Xem trước import](build/previews/native_import.png). Kết quả kiểm tra native được ghi trong `build/previews/native_smoke.json`, không chứa thông tin cá nhân sinh viên.

Ảnh Phase 2: [bảng điểm danh sau khi mở lại](build/previews/phase2_native_attendance.png), dùng hoàn toàn dữ liệu giả. Xem [hướng dẫn và tiêu chí nghiệm thu Phase 2](docs/phase-2.md); [Phase 1](docs/phase-1.md) được giữ để tham khảo.

Ảnh Phase 3 với dữ liệu giả: [QR trên Windows](build/previews/phase3_native_qr.png), [trang sinh viên](build/previews/phase3_student_form.png). Xem [hướng dẫn Phase 3](docs/phase-3.md).
