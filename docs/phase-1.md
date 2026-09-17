# Phase 1 — FA26, quản lý nhiều môn/lớp

## Phạm vi đã được duyệt

Desktop Windows; import Excel nhiều sheet; quản lý kỳ FA26; đọc mã môn, mã lớp, cặp ngày và slot từ tên sheet; lịch hôm nay/lịch tuần; xem trước và kiểm tra dữ liệu; lưu JSON và đọc lại khi mở app. Ngày bắt đầu 07/09/2026, ngày kết thúc và tổng buổi để trống.

## Cách nhận diện dữ liệu

- Học kỳ hiện cố định FA26, không suy đoán ngày kết thúc.
- Một lớp học phần có khóa `mã môn/mã lớp` trong file dữ liệu riêng của học kỳ. Không gộp các môn có cùng mã lớp.
- Tiền tố sheet quyết định lịch lặp; giữ lại tên sheet gốc để đối chiếu nguồn.
- `Class` của từng sinh viên phải khớp mã lớp trong tên sheet, theo xác nhận đã sửa dữ liệu của người dùng.
- Chuẩn hóa MSSV, mã môn/lớp sang chữ hoa, email sang chữ thường; bỏ khoảng trắng đầu/cuối. Giữ Unicode họ tên và MemberCode.
- Một SV đăng ký nhiều lớp được đếm một lần theo MSSV trong tổng sinh viên, nhưng mỗi đăng ký vẫn nằm trong danh sách môn tương ứng.
- Một MSSV có email khác nhau, hoặc một email thuộc nhiều MSSV, sẽ báo lỗi cần chỉnh sửa.
- Tên sheet sai, cột thiếu/trùng, dữ liệu bắt buộc trống, email sai, MSSV/email trùng trong sheet, Class không khớp, lớp học phần bị lặp hoặc công thức trong thông tin SV đều chặn import.
- Nếu hai lớp trùng giờ, hiển thị cảnh báo để GV kiểm tra; không tự sửa lịch.
- Workbook khác kỳ có mã FA/SP/SU trong tên file bị chặn. Tên file không chỉ rõ kỳ sẽ cảnh báo rằng dữ liệu được gán vào FA26.
- File phải là `.xlsx`, tối đa 25 MB; nội dung giải nén tối đa 64 MB.

## Đối chiếu file người dùng đã sửa

`FA26_Markbook.xlsx` đọc được 10 lớp học phần, 6 mã môn, 340 lượt đăng ký và 263 MSSV duy nhất. Không có lỗi/cảnh báo tại thời điểm kiểm tra.

| Sheet | SV | Lịch |
|---|---:|---|
| 11_PRN232_SE1917 | 35 | Thứ 2 + Thứ 5, slot 1 |
| 12_PRM393_SE1917 | 35 | Thứ 2 + Thứ 5, slot 2 |
| 13_PRM392_SE1920 | 36 | Thứ 2 + Thứ 5, slot 3 |
| 14_PRM393_SE1920 | 40 | Thứ 2 + Thứ 5, slot 4 |
| 22_SWD392_SE1927 | 35 | Thứ 3 + Thứ 6, slot 2 |
| 23_PRM232_SE1922 | 35 | Thứ 3 + Thứ 6, slot 3 |
| 24_PRM323_SE1928 | 33 | Thứ 3 + Thứ 6, slot 4 |
| 31_PRM323_SE1913 | 29 | Thứ 4 + Thứ 7, slot 1 |
| 33_PRN232_SE1919 | 37 | Thứ 4 + Thứ 7, slot 3 |
| 34_PRM323_SE1919 | 25 | Thứ 4 + Thứ 7, slot 4 |

## Các bước người dùng nghiệm thu trên bản Windows

1. Mở app chưa có dữ liệu: hiển thị hướng dẫn import, không tự điền lớp mẫu.
2. Chọn file FA26: thấy bản xem trước đủ 10 lớp/6 môn, xem được 40 SV của PRM393 – SE1920.
3. Hủy xem trước: dữ liệu đang lưu không thay đổi.
4. Xác nhận: tổng quan hiển thị 10 lớp, 6 môn, 263 sinh viên, 340 lượt đăng ký.
5. Lọc PRM393: chỉ còn SE1917 và SE1920. Tìm kiếm mã lớp và sinh viên trong từng lớp hoạt động.
6. Xem 07/09/2026: 4 lớp thứ 2; 08/09: 3 lớp thứ 3; 09/09: 3 lớp thứ 4; Chủ nhật 13/09: không có lớp.
7. Xem ngày trước 07/09: thông báo học kỳ chưa bắt đầu. Lịch tuần đúng cặp ngày và 4 khung giờ đã duyệt.
8. Đóng và mở lại: dữ liệu đã xác nhận vẫn còn; không cần import lại.
9. Thử file bị sai Class/email hoặc trùng MSSV: xem được lỗi theo sheet/dòng, nút lưu bị vô hiệu hóa, dữ liệu cũ không bị thay.
10. Import lại file hợp lệ: thông báo rõ thay toàn bộ dữ liệu FA26; sau xác nhận có file `.bak` giữ dữ liệu trước.

## Kiểm thử và giới hạn bàn giao

Kết quả: `flutter analyze` không có cảnh báo/lỗi; `flutter test` đạt **25/25 test**. Lệnh đọc file FA26 thực tế trả về `canSave: true` và danh sách lỗi rỗng. Test dựng hai ảnh giao diện cũng chạy thành công.

Kiểm thử tự động bao gồm đọc shared/inline strings và Unicode, ánh xạ cột, dữ liệu lỗi/trùng, biên giờ của 4 slot, ngày bắt đầu, lưu rồi đọc lại, sao lưu/phục hồi, chặn ghi dữ liệu sai, luồng import/hủy/lưu, lọc môn, tìm sinh viên và bố cục ở chiều rộng 800/1360 px. Ảnh giao diện được dựng với danh sách lớp thực tế, không xuất roster.

Đã cài Visual Studio Build Tools 2022 17.14.40 với workload C++ và Windows SDK, không yêu cầu khởi động lại. Flutter nhận toolchain Windows và build release thành công ngày 15/09/2026.

Kiểm tra trên ứng dụng Windows thực tế đã đạt:

- Mở `.exe` và render giao diện tiếng Việt.
- Nút Import mở hộp thoại chọn `.xlsx` của Windows; file người dùng hiển thị bản xem trước đủ 10 lớp/6 môn/340 lượt đăng ký/263 SV, không lỗi dữ liệu.
- Xác nhận import ghi `%APPDATA%\\FAPHelper\\FA26.json` đúng số lượng.
- Mở thêm một instance: tiến trình mới thoát mã 0, cửa sổ cũ tiếp tục hoạt động.
- Đóng cửa sổ bình thường rồi chạy lại: app tự hiển thị danh sách đã lưu. SHA-256 của file dữ liệu trước/sau khi mở lại giống nhau.
- Mở màn hình Lịch tuần và đối chiếu đúng các cặp ngày, 4 slot, mã môn/lớp và sĩ số.

Ảnh native và biên bản máy đọc được nằm tại `build/previews/native_*.png` và `build/previews/native_smoke.json`. Dữ liệu thật vẫn nằm trong thư mục ứng dụng của người dùng, không đưa vào mã nguồn hoặc bản ZIP. Các tình huống dữ liệu sai, phục hồi và biên giờ đã được kiểm tra tự động; bước chạy native tập trung vào import, khởi động lại, khóa một instance và lịch tuần.

Phase 1 đã sẵn sàng để người dùng chạy thử và duyệt. Bản chạy: `build/windows/x64/runner/Release/fap_helper_v1.exe`; khi sao chép cần giữ toàn bộ thư mục Release.

Phase 2 (P/A, chốt, sửa, thống kê, CSV) chưa bắt đầu. Đăng nhập SV, quy tắc mã bí mật, dịch vụ Internet không database và trang GV giả lập/extension sẽ được chốt trước phase tương ứng.
