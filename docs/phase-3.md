# Phase 3 — QR và đăng nhập Google

Windows v0.3.2. Dùng lại lớp, buổi học, lịch sử và file JSON của Phase 2; không dùng database. QR thường hoặc QR kèm mã bí mật. Người dùng đã chọn Google xác thực email, cho phép `gmail.com` và `fpt.edu.vn`; email phải có trong danh sách của đúng lớp.

Để dùng trang sinh viên trên domain Vercel cố định, làm theo [hướng dẫn triển khai Vercel](vercel-setup.md). Gói nguồn static đã chuẩn bị tại `deploy/student`; người dùng cần đăng nhập và triển khai lên tài khoản Vercel của mình.

## Chuẩn bị Google

1. Trong Google Cloud / Google Auth Platform, cấu hình ứng dụng và tạo OAuth Client ID loại **Web application**. Nếu ứng dụng đang ở chế độ Testing, thêm tài khoản thử phù hợp trong mục Test users.
2. Sao chép **Client ID** dạng `…apps.googleusercontent.com` vào app. Luồng này không cần Client Secret; không gửi mật khẩu Google hoặc FAP.
3. Thêm địa chỉ của trang sinh viên vào **Authorized JavaScript origins**. Chỉ nhập origin, ví dụ `https://diemdanh.example.edu.vn`, không thêm đường dẫn hay mã QR. Với kiểm tra trên cùng máy, thêm `http://localhost` và `http://localhost:8787`.
4. Dùng đúng tài khoản Google có email trong Excel. Đây là đăng nhập Google cho công cụ hỗ trợ độc lập, chưa tích hợp SSO FAP của trường.

Tham khảo chính thức: [tạo Client ID và origins](https://developers.google.com/identity/gsi/web/guides/get-google-api-clientid), [xác minh Google ID token](https://developers.google.com/identity/gsi/web/guides/verify-google-id-token).

### Nếu Google báo 401: invalid_client

Mã lỗi này chưa đủ để kết luận Client ID sai. Trong luồng đăng nhập web, Google cũng trả `invalid_client` khi origin không được cho phép; xem [mô tả lỗi chính thức](https://developers.google.com/identity/protocols/oauth2/javascript-implicit-flow#invalid_client).

1. Kiểm tra Client ID trong app khớp Client ID loại **Web application** đang mở trên Google Cloud, không dùng Client ID mẫu trong ảnh kiểm thử.
2. Mở QR và sao chép chính xác origin HTTPS dưới mục **Google Authorized JavaScript origins**. Thêm vào **Authorized JavaScript origins** của đúng Client ID, không nhầm với Authorized redirect URIs. Không thêm fragment `#…` hoặc đường dẫn.
3. Giữ cửa sổ QR và kết nối đang chạy trong lúc lưu cấu hình Google. Đóng/mở lại kết nối Quick Tunnel tạo origin mới; origin đã thêm trước đó không áp dụng cho địa chỉ mới.
4. Đợi Google áp dụng cấu hình, rồi quét mã mới ngay trong đợt QR đang mở và thử đăng nhập lại.

Nếu vẫn lỗi, lấy nguyên văn dòng giải thích bên dưới `invalid_client`. Nếu ghi **The OAuth client was not found**, cần đối chiếu lại Client ID và xem client còn tồn tại trong Google Cloud. Không thể xác minh quyền sở hữu/cấu hình client chỉ từ chuỗi Client ID lưu trên máy.

## Sử dụng trên Windows

1. Giải nén toàn bộ `FAPHelper-Phase3-Windows-x64.zip`; chạy `fap_helper_v1.exe`. Giữ các DLL, thư mục `data` và `cloudflared.exe` cạnh app.
2. Vào **Cấu hình** trên sidebar: nhập Client ID, miền email (`gmail.com, fpt.edu.vn`), chọn cách kết nối và địa chỉ HTTPS cố định nếu dùng. Bấm **Lưu cấu hình**. Cấu hình dùng chung cho các lớp và giữ lựa chọn kết nối khi mở lại. Có thể cấu hình trước khi import Excel.
3. Mở lớp, chọn đúng buổi đã đến giờ, bấm **Mở buổi**, sau đó **Điểm danh QR**. Màn hình này đọc cấu hình đã lưu và chỉ giữ tùy chọn **QR + mã bí mật** cho từng đợt nhận.
4. Bấm **Bắt đầu nhận QR**. Nếu dùng địa chỉ thử nghiệm, sao chép origin xuất hiện dưới QR sang cấu hình Google; đợi Google áp dụng rồi quét QR mới.
5. SV dùng camera quét QR, mở bằng Chrome/Safari, đăng nhập Google, kiểm tra thông tin, nhập mã nếu được yêu cầu rồi bấm **Xác nhận có mặt**. Không mở trong trình duyệt nhúng nếu Google từ chối đăng nhập.
6. App GV cập nhật số đã có mặt sau mỗi lần lưu thành công. Bấm **Chốt danh sách** để dừng nhận và chuyển ô trống thành A. **Dừng nhận QR và quay lại** chỉ dừng nhận, vẫn giữ buổi đang mở; có thể tiếp tục thủ công hoặc mở đợt QR mới.
7. Trở lại bảng điểm danh để xem P/A, lịch sử QR/Google, sửa có lý do hoặc xuất CSV theo Phase 2.

## Kết nối từ hai mạng khác nhau

- **Internet · trang sinh viên trên Vercel:** trang SV được triển khai lên domain production cố định. Nhập domain này vào app và Google origins. App tự mở Quick Tunnel cho API máy GV và đưa địa chỉ API vào fragment QR; không cần đổi Google origins theo địa chỉ tunnel. Vẫn cần giữ app/mạng của GV hoạt động. CORS chỉ cho phép origin đã cấu hình. Xem [các bước triển khai](vercel-setup.md).

- **Internet · địa chỉ thử nghiệm Cloudflare:** app mở kết nối ra Internet và nhận origin HTTPS tạm. GV/SV không cần cùng Wi-Fi, không cần mở cổng vào máy. Địa chỉ đổi khi tạo kết nối mới nên cần cập nhật Google origins. Dùng cho thử nghiệm; Quick Tunnel không có cam kết uptime và không phải hình thức triển khai production. Xem [giới hạn Quick Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/).
- **Internet · địa chỉ HTTPS cố định:** dành cho tên miền và reverse tunnel đã được cấu hình, trỏ tới `http://127.0.0.1:8787` trên máy GV. Nhập origin HTTPS vào app và Google. Đây là đường nâng cấp để dùng ổn định, không cần sửa origin mỗi buổi. App không tự tạo DNS/tài khoản Cloudflare/tunnel cố định.
- **Thử trên máy này · localhost:** chỉ kiểm tra bằng trình duyệt trên chính máy GV. Điện thoại ở mạng khác không dùng được địa chỉ localhost.

Kết nối hoạt động trong lúc cửa sổ QR và app còn mở. Đóng cửa sổ QR sẽ dừng server và tunnel thử nghiệm. Windows job object cũng kết thúc tiến trình tunnel khi app bị đóng. Không có dịch vụ chạy nền để tiếp tục nhận khi máy GV tắt hoặc mất mạng. Kiểm tra Wi-Fi chưa triển khai.

## Quy tắc phiên QR

- Mỗi đợt nhận gắn cố định với học kỳ/môn/lớp/buổi; đổi lớp hoặc buổi cần dừng đợt cũ.
- QR chứa token ngẫu nhiên 256 bit, đổi mỗi 15 giây. Token cũ không đổi được lượt quét mới. Mã nằm trong fragment URL để không đi vào log đường dẫn HTTP; trang xóa fragment sau khi đọc.
- Quét hợp lệ đổi lấy một lượt có hạn 3 phút. Lượt quét có nonce riêng gắn với đăng nhập Google; không nhận lại token Google của lượt quét khác. Thời hạn 3 phút không cho phép gửi sau khi GV đã dừng/chốt.
- Mã bí mật có 6 chữ số, sinh riêng khi bắt đầu đợt nhận và giữ nguyên trong đợt đó. Không chứa trong QR và không gửi qua API sinh viên. Nhập sai tối đa 5 lần/lượt; hết lượt thì quét lại. Mã bí mật này là mã lớp học, không phải OTP tài khoản Google.
- Chỉ máy GV tạo/dừng/chốt phiên. Server công khai chỉ cung cấp trang SV và 3 API quét/đăng nhập/gửi; không cung cấp danh sách lớp, roster, file JSON, sửa điểm danh hoặc API quản trị.
- Máy GV xác minh chữ ký RS256 bằng khóa Google, issuer/audience/expiry/nonce, email đã xác minh, miền cho phép và danh sách lớp. Email FPT phải là tài khoản Google Workspace thuộc miền cho phép; Gmail được Google quản lý trực tiếp.
- Mọi thay đổi JSON được xếp hàng; gửi trùng P không tạo thêm lịch sử. Chốt đợi thao tác lưu đã bắt đầu hoàn tất, từ chối yêu cầu còn lại rồi chuyển ô trống thành A. Ghi file lỗi thì không báo điểm danh thành công và cho phép thử lại.
- Nếu GV đã ghi A thủ công, SV không tự đổi A thành P qua QR; cần GV kiểm tra. Lịch sử phân biệt **Điểm danh QR · Google** và điểm danh thủ công.
- Dừng/chốt/khởi động lại app làm mất toàn bộ token/lượt quét trong RAM. P/A đã lưu vẫn còn. Mỗi đợt nhận tối đa 3 giờ; hết hạn cần quay lại mở đợt mới. QR không chứng minh vị trí vật lý của người quét.

## Dữ liệu

- Điểm danh: `%APPDATA%\FAPHelper\FA26.json` và bản sao của Phase 2.
- Cấu hình: `%APPDATA%\FAPHelper\qr-settings.json`, chứa Client ID công khai, miền email, cách kết nối và origin HTTPS cố định. File cũ không có cách kết nối vẫn đọc được: có origin cố định thì dùng kết nối cố định, còn lại dùng Cloudflare thử nghiệm. Không lưu Google ID token, cookie, mật khẩu hoặc mã bí mật vào file.
- Không tự sửa Excel, không import lại hoặc thêm P/A thử vào dữ liệu thật trong quá trình kiểm thử. Dữ liệu thử nằm riêng trong `build` hoặc thư mục tạm.

## Kiểm thử và phần cần cấu hình

Đã có kiểm thử chữ ký RSA bằng khóa thử riêng, từ chối token giả/sai audience/hết hạn/nonce/email, QR 15 giây, lượt quét 3 phút, mã bí mật, gửi đồng thời/trùng, lỗi ghi file, chốt trong lúc lưu, dừng khi đang xác thực và HTTP thực tế lưu/đọc JSON. Giao diện cấu hình được kiểm tra ở 800×600. Đây không phải bằng chứng đã đăng nhập Google bằng tài khoản thật.

Người dùng đã nhập Client ID loại Web application. Cần thêm đúng origin của đợt QR vào Google Authorized JavaScript origins và nghiệm thu đăng nhập Google thật. Không có chế độ bỏ qua xác thực trong bản release. Chưa triển khai trang GV giả lập FAP và Chrome extension; các phần này thuộc phase sau.

Kết quả ngày 15/09/2026: **62/62 kiểm thử đạt**, phân tích mã không có lỗi, build Windows release thành công. Native đã tạo Quick Tunnel, tải trang và đổi lượt quét qua HTTPS công khai, từ chối token Google giả, tự đổi QR và từ chối QR cũ, chốt thành A/A/A trên 3 SV giả rồi đóng server/tunnel. Chrome ở 390×844 đã kiểm tra form, sai mã/nhập lại, callback đăng nhập giả dành riêng cho test và lưu P. Không sử dụng roster thật trong các phiên công khai thử nghiệm.

Bằng chứng: `build/previews/phase3-native.json`, `phase3-browser.json`; ảnh [QR Windows](../build/previews/phase3_native_qr.png), [form SV](../build/previews/phase3_student_form.png), [ghi P thành công trong test](../build/previews/phase3_student_success.png). Địa chỉ thử nghiệm trong ảnh đã dừng sau kiểm tra.

Lệnh build/test:

```powershell
& 'D:\Flutter\flutter\bin\flutter.bat' analyze
& 'D:\Flutter\flutter\bin\flutter.bat' test
& 'D:\Flutter\flutter\bin\flutter.bat' build windows --release
powershell -ExecutionPolicy Bypass -File tool\package_phase3.ps1
```

Script đóng gói tải cloudflared từ release chính thức đã ghim phiên bản/checksum, rồi đóng gói toàn bộ thư mục Release. Không chứa dữ liệu FA26 của giảng viên.
# Reset điểm danh (v0.3.3)

Vào **Cấu hình → Dữ liệu điểm danh → Reset dữ liệu điểm danh**. Chọn một lớp học phần hoặc toàn bộ kỳ FA26, nhập `RESET` rồi xác nhận.

Các dấu P/A được xóa; buổi đã mở/chốt trở về chưa mở. Giữ danh sách sinh viên, lịch học, tổng số buổi, ngày nghỉ, học bù, cấu hình Google/kết nối và lịch sử thao tác; thêm một dòng lịch sử reset. CSV đã xuất trước đó không tự thay đổi, cần xuất lại sau khi điểm danh lại.

App tạo bản sao đầy đủ trong thư mục dữ liệu `backups/FA26-before-reset-<timestamp>.json` trước khi lưu thay đổi và hiển thị đường dẫn sau khi hoàn tất. Bản sao này không bị thay thế bởi bản sao `.bak` thường kỳ. Nếu không sao lưu được, app không reset. Quay về màn hình chính sau khi dừng QR để dùng chức năng này.
