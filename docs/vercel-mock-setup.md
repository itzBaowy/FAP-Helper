# Đưa trang GV giả lập lên Vercel

Áp dụng cho extension **v0.4.2**. Giao diện ở domain Vercel cố định; chương trình trên máy GV mở kết nối Cloudflare HTTPS, kiểm tra khóa truy cập và lưu JSON như trước. Không dùng database. Máy GV phải bật chương trình kết nối và có Internet khi dùng trang.

## 1. Deploy trang GV thành project riêng

Mở PowerShell và chạy:

```powershell
Set-Location 'D:\Projects\FAP-Helper\fap_helper_v1'
powershell -NoProfile -ExecutionPolicy Bypass -File tool\prepare_mock_vercel.ps1
Set-Location deploy\mock-fap
npx.cmd vercel login
npx.cmd vercel --prod
```

Nếu đã đăng nhập Vercel thì bỏ qua `vercel login`.

- Xác nhận cài Vercel CLI nếu npm hỏi.
- `Set up and deploy?`: chọn Y.
- Chọn tài khoản của bạn.
- `Link to existing project?`: chọn **N** ở lần đầu. Tạo project riêng, không chọn project trang sinh viên.
- Project name: ví dụ `fap-helper-gv` (tên thực tế tùy khả dụng).
- Thư mục nguồn: `./`.
- Framework: **Other**, Output Directory: **public**, không cần Build Command hay environment variables.

Chỉ deploy thư mục `deploy/mock-fap`. Thư mục đã chuẩn bị chứa HTML/CSS/JS và cấu hình hosting; không có file sinh viên, CSV, Excel hoặc khóa truy cập. Không deploy toàn bộ thư mục dự án hay `mock-fap` chứa server Node.

## 2. Lấy domain production

Vào Vercel → project trang GV → **Settings → Domains**, lấy domain production dạng:

```text
https://fap-helper-gv.vercel.app
```

Đây là ví dụ; thay bằng domain thật của bạn ở tất cả bước sau. Không dùng URL preview hay URL riêng của một deployment. Bản hiện tại hỗ trợ domain `*.vercel.app`.

Nếu mở trang trực tiếp thấy “Chưa kết nối máy GV”, đó là trạng thái chờ kết nối bình thường. Tiếp tục bước 3.

Nếu trang yêu cầu đăng nhập **Vercel**, đây là **Settings → Deployment Protection**. Bạn có thể giữ bảo vệ nếu chỉ mình bạn sử dụng; nếu cần mở ở trình duyệt/máy khác mà không đăng nhập Vercel, cho phép truy cập domain production. Khóa kết nối GV ở bước sau vẫn cần để đọc/ghi dữ liệu. Trang giả lập không dùng Google OAuth nên không cần thêm domain này vào Google Client ID của trang sinh viên.

## 3. Bật kết nối từ máy GV

Nếu cửa sổ `mock-fap/start.ps1` đang chạy, nhấn **Ctrl+C trong cửa sổ đó** để dừng trước; hai chế độ dùng chung     cổng 8990 và cùng file JSON. Không cần dừng desktop hoặc QR sinh viên.

Mở PowerShell tại thư mục dự án, chạy (thay domain mẫu):

```powershell
Set-Location 'D:\Projects\FAP-Helper\fap_helper_v1'
powershell -NoProfile -ExecutionPolicy Bypass -File mock-fap\start-vercel.ps1 -Origin 'https://fap-helper-lecturer.vercel.app'
```

Chương trình dùng Node.js và file `build/windows/x64/runner/Release/cloudflared.exe` đã có trên máy này. Nếu dùng bản giải nén ở máy khác, chỉ rõ vị trí cloudflared trong gói desktop:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File mock-fap\start-vercel.ps1 -Origin 'https://fap-helper-gv.vercel.app' -Cloudflared 'D:\FAPHelper\cloudflared.exe'
```

Chờ chương trình in liên kết dạng `https://…vercel.app/#api=…&key=…`, sao chép **toàn bộ liên kết đó** vào Chrome. Liên kết có khóa quản lý danh sách/điểm danh; chỉ dùng cho GV, không gửi cho SV. Trang xóa phần khóa khỏi thanh địa chỉ sau khi đọc và giữ kết nối trong phiên tab để tải lại trang được.

Giữ cửa sổ kết nối mở. Khi tắt hoặc khởi động lại chương trình, mở lại liên kết mới chương trình cung cấp. Domain Vercel vẫn giữ nguyên và không cần deploy lại. Đóng tab rồi mở domain thuần sẽ cần mở lại liên kết GV để kết nối.

## 4. Cấu hình extension

1. Vào `chrome://extensions`, **Reload / Tải lại** FAP Helper để dùng v0.4.2; nếu Chrome yêu cầu chấp nhận quyền lưu cấu hình, xác nhận trong giao diện Chrome.
2. Mở trang GV bằng liên kết ở bước 3, bấm biểu tượng extension.
3. Cuộn tới **Địa chỉ trang giả lập**, nhập domain production, ví dụ `https://fap-helper-gv.vercel.app`, rồi bấm **Lưu địa chỉ**. Chỉ nhập domain, không nhập `#api=…&key=…`.
4. Chọn CSV, chọn buổi, **Đối chiếu với tab hiện tại → Điền P/A và submit** như trước.

Extension chỉ cho phép localhost và domain Vercel đã lưu. Quyền `storage` mới chỉ dùng lưu domain; không lưu CSV, danh sách SV hay khóa kết nối trong extension.

## 5. Nhập Excel và kiểm tra

Trang Vercel dùng lại `%APPDATA%\FAPHelper-Mock\mock-fa26.json` trên máy GV. Nếu đã nhập dữ liệu ở localhost, dữ liệu đó vẫn hiện sau khi kết nối.

Bấm **Import Excel** và chọn file `.xlsx` của học kỳ FA26. Trang đọc trực tiếp file trong trình duyệt; file Excel không được tải lên Vercel. Quy ước dữ liệu giống ứng dụng desktop:

- Mỗi sheet là một lớp, tên theo mẫu `11_PRN232_SE1917`: số đầu là cặp ngày 1–3, số thứ hai là slot 1–4, sau đó là mã môn và mã lớp.
- Dòng dữ liệu đầu tiên của mỗi sheet phải có đủ `Class`, `RollNumber`, `Email`, `MemberCode`, `FullName`; thứ tự cột có thể thay đổi.
- Trang nhập toàn bộ sheet hợp lệ, danh sách sinh viên, cặp ngày, slot và khung giờ. Các ngày học được tạo từ 07/09/2026 đến 14 ngày sau ngày import để có thể chọn và nhận CSV từ extension.
- Sheet sai tên, thiếu cột, sai lớp/email, trùng MSSV/email hoặc dùng công thức trong thông tin sinh viên sẽ chặn toàn bộ lần import và hiển thị lỗi.

Trang vẫn nhận `FA26.json` phiên bản 2 để tương thích với quy trình cũ và có thể dùng `mock-fap/demo/FA26-demo.json` để thử nhanh.

Dùng CSV tương ứng để chuyển một buổi. Sau khi submit thành công, tải lại tab để xác nhận P/A được giữ. Dữ liệu được lưu trên máy GV, không được tải vào project Vercel.

## Cập nhật lần sau

```powershell
Set-Location 'D:\Projects\FAP-Helper\fap_helper_v1'
powershell -NoProfile -ExecutionPolicy Bypass -File tool\prepare_mock_vercel.ps1
Set-Location deploy\mock-fap
npx.cmd vercel --prod
```

Dùng lại project đã liên kết. Nếu có cập nhật server kết nối, dừng chương trình cũ bằng Ctrl+C, chạy lại và mở liên kết mới. Nếu extension thay đổi, Reload trong Chrome.

## Kiểm tra đã thực hiện

- 6 nhóm kiểm thử Node đạt, gồm API từ chối sai origin, thiếu/sai khóa, kiểm tra CORS, lưu file và khởi động lại.
- 13 kiểm tra trình duyệt localhost và 14 kiểm tra chế độ Vercel đạt, chạy extension thật; Vercel/Cloudflare được ánh xạ tới server thử nghiệm riêng. Kiểm tra xóa fragment, reload giữ kết nối, đối chiếu, điền-submit và lỗi lưu.
- Chưa deploy vào tài khoản Vercel của bạn. Bước deploy và kiểm tra domain thật do bạn thực hiện theo hướng dẫn.

Tham khảo chính thức: [deploy bằng CLI](https://vercel.com/docs/projects/deploy-from-cli), [cấu hình vercel.json](https://vercel.com/docs/project-configuration/vercel-json), [Deployment Protection](https://vercel.com/docs/deployment-protection).
