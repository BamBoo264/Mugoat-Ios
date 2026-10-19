# Mugoat iOS Recovery v1

## Đã triển khai

Phục hồi host iOS C/Metal, UI và cầu nối multiplayer từ bản source Mugoat còn
lưu trên máy. Đây là source hybrid thực tế, không phải hai runtime chạy chồng
lên nhau. Đã tải hai upstream đang hoạt động để đối chiếu và lưu commit trong
`UPSTREAMS.json`. Không tuyên bố đây là toàn bộ HEAD mới nhất đã được merge.

Bundle mới `vn.iosvn.mugoat.recovery` cài riêng; giữ native renderer, Story,
Sandbox, controller/touch, save backup/import, networking/voice của snapshot.
Không sửa game data gốc, save hoặc source/release PC V10.

Đã thay quy trình tải game từ mirror cũ, mã hóa bằng secret của repo đã mất và
auto-publish release bằng workflow độc lập cho repo Private của người dùng.
Đầu vào 73.523.495 byte gồm engine, manifest và shader packs từ chính bộ data
hiện có; không gồm 20 GB archive hoặc save. Source backup offline không có
những file đầu vào game này.

Đã sửa metadata app ở cả Info.plist và XcodeGen, thêm kiểm tra đồng nhất để
XcodeGen không ghi đè tên/version trở lại giá trị cũ. Đã thêm cache engine đã
chuyển đổi, Metal và sản phẩm Xcode; cache phân biệt input/compiler/codegen,
loại Python bytecode phụ thuộc thời gian ra khỏi khóa.

Đã loại hành vi `pg_streamed_txd_loaded` trả về thành công cho dictionary không
có trong data. Host trả nguyên kết quả tải thật của engine. Không ép nhiệm vụ
hoàn thành hoặc giả điều kiện đã tải.

## Đã kiểm chứng

- 6 kiểm thử Rust: ABI FFI, giới hạn truy cập RAM và các trường hợp protocol.
- 3 kiểm thử typed codegen và vị trí hook.
- 5 kiểm thử đầu vào/checksum/traversal/không ghi đè và identity XcodeGen.
- UDP integration: join/relay/leave/rejoin, room isolation và biên 32/64 người.
- Hash engine và shader index khớp đúng build `8b0b5899ed`.
- Engine memory64 ABI thật, hỗ trợ import RAM 3..16 GiB; đây là ABI/reservation,
  không phải cam kết iOS cấp 16 GiB RAM vật lý.
- Xuất 215 native mà không thay đổi chỉ số hàm gốc; 24 alias tùy chọn vắng mặt.
- `proto.rs` và `server.rs` giống PC V10 sau chuẩn hóa xuống dòng.
- CI macOS vượt các kiểm thử C/C++ input/RAM/FPS, Swift camera/mod path/save.
- Lượt baseline build thành công cả IPA ARM64 và Metal, 4.808 shader/100 water
  programs, không có shader biên dịch lỗi; xác thực cấu trúc và codesign strict
  thành công. Kết quả **bản cuối** nằm trong `BUILD-STATUS.json`, phân biệt rõ
  với lượt baseline trước khi bỏ báo tải texture giả.
- Bản cuối đã build thành công, tải về PC và đối chiếu SHA-256 khớp CI; đúng
  source revision `bb6098232e50e962a32db4038152ed30e96871ee`, version 2.1 (21).
  Đọc mã ARM64 trong cả hai IPA xác nhận helper texture chỉ `mov x0, x3; ret`,
  trả lại đối số load thật, không còn nhánh ép thành công. Xem
  `../Mugoat-iOS-Recovery-v1-IPAs/TXD-BINARY-VALIDATION.json` trên PC.

Log baseline còn cảnh báo guard gián tiếp không khớp f91082/f10006; không sửa
theo suy đoán. Build thành công không xác nhận guard đó cần/đã áp dụng cho mọi
đường gameplay; cần log thiết bị nếu phát sinh trap.

## Giới hạn

Chưa chạy trên iPhone thật, chưa đo FPS/nhiệt/Jetsam, cutscene/nhiệm vụ dài hoặc
chơi chung iPhone ↔ PC. ESign phải ký lại IPA ad-hoc. Entitlement RAM phụ thuộc
chứng chỉ/provisioning profile thực tế.

Data rút gọn thiếu `MPShopSale` vẫn có thể chặn Los Santos Customs. Bản phục
hồi không bổ sung asset đó hoặc dùng cách báo tải giả để che vấn đề.

Chưa chuyển tính năng add-on/spawn/audio fallback V10 từ PC. Những điểm mở rộng
được ghi trong `IOS-MODS-NEXT.md`; không mặc định mọi mod GTA V PC tương thích.

Source: `https://github.com/BamBoo264/Mugoat-Ios` (Private).
