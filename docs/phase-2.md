# Phase 2 — Điểm danh thủ công, chốt và CSV

Phiên bản **0.2.0**, Windows, học kỳ FA26. Kế thừa các lớp đã import ở Phase 1 và tiếp tục lưu JSON, không dùng database. QR, đăng nhập sinh viên, dịch vụ Internet và Chrome Extension thuộc các phase sau.

## Cách sử dụng

1. Bấm một lớp từ Tổng quan, Lớp học phần hoặc Lịch tuần để mở bảng điểm danh. Nút **Danh sách SV** mở thông tin đầy đủ; rê chuột lên họ tên trong bảng để xem email/MemberCode.
2. Chọn đúng **buổi, ngày và slot** bằng bộ chọn hoặc tiêu đề cột. Mỗi trang bảng hiển thị tối đa 8 buổi, có nút chuyển trang. Buổi đang trong giờ được highlight theo GMT+7; buổi đang chọn có nền khác.
3. Bấm **Mở buổi**. Chỉ mở được buổi đã đến giờ bắt đầu; có thể mở buổi cũ để nhập điểm danh thủ công. Một lớp chỉ có một buổi đang mở. Đóng app không tự chốt buổi.
4. Bấm ô của SV trong cột đang chọn rồi chọn **P · Có mặt**, **A · Vắng** hoặc **— · Chưa ghi nhận**. Mỗi thay đổi được lưu ngay sau khi ghi file thành công.
5. Bấm **Chốt danh sách** và kiểm tra thông báo: các SV chưa ghi nhận của **toàn bộ lớp** sẽ chuyển thành A, kể cả khi bảng đang lọc tìm kiếm. Các P/A đã ghi được giữ nguyên.
6. Sau khi chốt, bấm ô để sửa P/A. Cần nhập lý do ít nhất 3 ký tự. Không thể đưa ô đã chốt về trạng thái trống hoặc mở lại buổi đã chốt. Xem thao tác trong **Lịch sử**.
7. Bấm **Xuất CSV** → xuất buổi đang chọn hoặc tất cả buổi đã chốt của lớp → chọn nơi lưu bằng hộp thoại Windows. Buổi chưa chốt không được xuất.

## Buổi học, lịch và thống kê

- Lịch tuần gốc lấy từ tiền tố sheet, bắt đầu từ 07/09/2026 và giữ 4 khung giờ đã thống nhất. Một slot trong ngày là một buổi điểm danh.
- Khóa lưu buổi là `YYYY-MM-DD/slot`, nằm trong lớp học phần và học kỳ. Thay đổi thứ tự hiển thị do nghỉ/học bù không chuyển kết quả của SV sang ngày khác.
- Nếu chưa nhập tổng, bảng sinh lịch dự kiến tới hôm nay + 14 ngày và tới ngày xa nhất có dữ liệu/đang xem. Buổi tương lai để trống, không tự ghi A.
- **Tổng số buổi** là cấu hình riêng cho lớp. Nhập số buổi theo lịch tuần gốc (1–200), hoặc để trống nếu chưa xác định. Đây không phải ngày kết thúc học kỳ.
- **Đánh dấu nghỉ** chỉ áp dụng cho buổi chưa mở/chưa có điểm danh, cần lý do; không tạo A. Có thể khôi phục buổi nghỉ về chưa mở.
- **Thêm học bù** cho phép chọn ngày từ mốc đầu kỳ, slot và lý do. Không cho trùng ngày/slot của lớp hoặc trùng lịch dạy một lớp khác. Nếu học bù thay buổi nghỉ, cần đánh dấu nghỉ buổi gốc để không tăng tổng phải học.
- Khi đã cấu hình N buổi gốc: **Tổng phải học = N − số buổi gốc đã nghỉ + số buổi học bù còn hiệu lực**. Số thứ tự buổi trên bảng bỏ qua buổi nghỉ.
- **Tỷ lệ vắng = tổng A / tổng phải học × 100%**. Khi chưa biết tổng hoặc tổng bằng 0, hiển thị `—`. P/A được thống kê từ các giá trị đã ghi, không suy ra từ việc ngày học đã qua.
- Đổi tổng không được làm mất buổi đã lưu hoặc làm lịch gốc trùng một buổi học bù đang có.
- **Tổng quan theo ngày** đã áp dụng ngày nghỉ, học bù và tổng số buổi. **Lịch tuần** vẫn là lịch gốc từ Excel và có nhãn giải thích rõ.

## Lưu dữ liệu và import lại

- Dữ liệu nằm tại `%APPDATA%\FAPHelper\FA26.json`. Schema 2 bổ sung `attendance`, chứa cấu hình, các buổi đã thao tác và lịch sử của từng lớp.
- File schema 1 từ Phase 1 vẫn đọc được, giữ nguyên toàn bộ danh sách. Lần ghi tiếp theo sẽ lưu schema 2; file trước đó được giữ trong `.bak`.
- Chỉ cập nhật kết quả trên giao diện sau khi file đã ghi thành công. Trong lúc lưu, các nút thay đổi dữ liệu và nút quay lại bị khóa. Nếu ghi thất bại, báo lỗi và giữ trạng thái trước thao tác.
- Lịch sử gồm mở/chốt buổi, từng thay đổi P/A trước và sau, lý do sửa, cấu hình tổng, nghỉ/khôi phục/học bù. Thời gian được lưu UTC và hiển thị GMT+7. Đây là nhật ký local, không phải nhật ký chống chỉnh sửa file.
- Import lại cùng mã môn/lớp, lịch và tập MSSV sẽ giữ nguyên điểm danh/cấu hình/lịch sử, đồng thời cập nhật thông tin SV từ Excel.
- Không cho import xóa lớp, đổi lịch hoặc thêm/bớt MSSV của lớp đã có điểm danh/cấu hình/lịch sử, vì cần quy trình điều chỉnh đăng ký học riêng. Lớp chưa có dữ liệu điểm danh vẫn có thể được thay như Phase 1. Khi có lỗi, toàn bộ lần import bị chặn, dữ liệu cũ không đổi.
- Không dùng bản Phase 1 cũ để ghi lại file đã nâng cấp lên schema 2.

## Hợp đồng CSV dành cho phase extension

File UTF-8 có BOM, dấu phẩy phân tách, CRLF kết thúc dòng. Mỗi trường được bọc bằng dấu nháy kép; nháy kép trong nội dung được nhân đôi theo [quy tắc CSV của RFC 4180](https://www.rfc-editor.org/rfc/rfc4180). Nội dung có dấu phẩy, xuống dòng và tiếng Việt được giữ trong một trường CSV. Giá trị có thể được Excel hiểu là công thức được thêm dấu nháy đơn ở đầu để hiển thị như văn bản.

Mỗi hàng ứng với **một sinh viên trong một buổi đã chốt**:

| Cột | Ý nghĩa |
|---|---|
| SchemaVersion | `1` cho định dạng CSV này (khác schema JSON) |
| Term | `FA26` |
| SubjectCode, ClassCode | Mã môn, mã lớp học phần |
| SessionId | `FA26/SubjectCode/ClassCode/YYYY-MM-DD/slot` — khóa đối chiếu chính |
| SessionNumber | Thứ tự buổi trong lịch hiện tại, bỏ qua buổi nghỉ |
| Date | Ngày học `YYYY-MM-DD` |
| Slot | Slot trong ngày, 1–4 |
| StartTime, EndTime | Giờ học Việt Nam `HH:mm` |
| RollNumber | MSSV, khóa đối chiếu sinh viên |
| Email, FullName, MemberCode | Thông tin SV hiện tại |
| Status | Chỉ `P` hoặc `A` |
| ClosedAt | Thời điểm chốt ban đầu, ISO 8601 UTC |
| ExportedAt | Thời điểm xuất file, ISO 8601 UTC |

Xuất lại sau khi sửa sẽ lấy P/A mới nhất. `SessionId` và `RollNumber` là khóa ổn định; không dùng số dòng hoặc chỉ `SessionNumber` để đối chiếu trên trang giả lập/FAP. CSV chưa được tự gửi lên website nào trong Phase 2.

## Nghiệm thu

- Mở lớp đã import ở Phase 1, kiểm tra danh sách còn nguyên và các buổi chưa điểm danh đều trống.
- Mở một buổi đã đến giờ, ghi P cho một vài SV, tìm kiếm để ẩn các SV khác rồi chốt. Kiểm tra mọi ô còn trống của buổi được chuyển A, buổi khác không đổi.
- Nhập tổng 20: SV vắng 1 buổi phải hiển thị 5.0%; xóa tổng thì tỷ lệ trở về `—`.
- Thử sửa sau chốt: không có lý do thì không lưu; có lý do thì đổi P/A, có bản ghi lịch sử trước/sau. Đóng và mở lại app vẫn còn kết quả và lý do.
- Đánh dấu một buổi chưa mở là nghỉ; thêm buổi học bù ở ngày/slot không trùng lịch. Kiểm tra lịch theo ngày và tổng phải học cập nhật đúng.
- Xuất CSV một buổi và tất cả buổi đã chốt; không lẫn buổi chưa chốt. File mở được bằng Excel và có đủ thông tin học kỳ/môn/lớp/buổi/MSSV/P/A.
- Import lại file cùng lịch/tập MSSV: điểm danh còn nguyên; file làm mất SV/lớp đã có dữ liệu bị chặn.

## Kiểm thử phát triển

`flutter analyze` và `flutter test` bao gồm hồi quy Phase 1, nâng cấp schema, điểm danh/chốt/sửa, giữ dữ liệu khi import lại, CSV, ghi file thất bại và bố cục 800×600.

`tool/prepare_phase2_smoke.dart` tạo hồ sơ giả riêng trong `build/phase2-smoke-profile`. Khi chạy native để kiểm thử, đặt biến môi trường riêng cho tiến trình con `FAP_HELPER_DATA_DIR` tới thư mục này. Không đặt biến đó khi sử dụng dữ liệu thật. Test tự động dùng tên giả/MSSV giả/email `example.com`; không thêm P/A thử vào hồ sơ giảng viên thật.

Ngày 15/09/2026: `flutter analyze` không có lỗi; **47/47 kiểm thử đạt**; `flutter build windows --release` thành công. Đã kiểm tra trực tiếp trên Windows với hồ sơ giả: mở buổi, ghi P, chốt ô trống thành A, sửa A → P có lý do, xuất CSV qua hộp thoại Windows và đóng/mở lại app. CSV có UTF-8 BOM, 17 cột, đủ 3 SV với kết quả P/P/A; lý do sửa và kết quả vẫn còn sau khi mở lại. So sánh SHA-256 xác nhận file FA26 thật không đổi.

Ảnh nghiệm thu: [bảng điểm danh sau khi mở lại](../build/previews/phase2_native_attendance.png). Kết quả máy đọc được: `build/previews/phase2-native.json`. Bản đóng gói: `build/FAPHelper-Phase2-Windows-x64.zip`; giải nén toàn bộ rồi chạy `fap_helper_v1.exe`.
