# iOS 2.4 (24): SH150 / 27rev

Kiểm tra trực tiếp hai RPF người dùng cung cấp:
- SH150: vehicles.meta có comment `<!-----...>` chứa `--` không hợp chuẩn XML; parser iOS từ chối. Có texture parent `vehicles_biker_shared` không được khai báo trong vehicles.meta của bộ data rút gọn.
- 27rev: texture parent `vehicles_race_generic` cũng không có trong dữ liệu cơ sở đã đối chiếu; nhận DLC chưa chứng minh model stream được. Chưa có log iPhone xác nhận riêng điểm gây chờ spawn, vì vậy cần test sau chuyển đổi.
- Hai layout LAYOUT_BIKE_SCOOTER / LAYOUT_LOW_RESTRICTED đều đã có trong data gốc. Gói PC kèm thêm bảng layout không cần chép đè lên bản port.

Importer mới chuẩn hóa comment, đối chiếu TXD parent với metadata game và YTD trong mod, dùng vehshare khi parent chưa được xác minh; đóng gói DLC phẳng theo cơ chế PC. Giữ nguyên bytes YFT/YTD và tuning parts; không đòi mỗi tuning fragment có YTD riêng, không liệt kê phụ tùng thành xe spawn. Giữ tên DLC để nhập lại cập nhật pack đang có. Bỏ bảng layout trùng gốc chỉ sau khi kiểm tra mọi layout được xe yêu cầu đã có; custom layout chưa hỗ trợ sẽ báo lỗi.

Cài IPA 2.4, chọn đúng thư mục game trước, nhập lại SH150 và 27rev qua Mod Manager, rồi mở lại Story offline. Spawn name: `sh150`, `27rev`. Không cần nhập lại Vision nếu đang chạy được. Sửa âm thanh 2.3 và cache Metal vẫn được giữ.

CI kiểm tra XML comment không hợp chuẩn, giữ kiểm tra lỗi XML thật, chuyển parent thiếu sang vehshare, giữ tên pack và không biến tuning fragment thành vehicle. Chưa test spawn thực tế trên iPhone. Workflow chỉ tạo Mugoat-Cert-Paid.ipa.
