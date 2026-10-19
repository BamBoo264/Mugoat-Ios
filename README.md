# Mugoat iOS Recovery v1

Bản phục hồi source iOS Mugoat từ snapshot còn lưu trên PC, dùng host native
C/Metal của GTA5 iOS Port và cầu nối Rust cho multiplayer Muguet/Mugoat.
Không phải bản phát hành chính thức của IOSVN hoặc hai tác giả upstream.

## Nền tảng và phạm vi

- Engine `game.wasm` build `8b0b5899ed` được wasm2c dịch sang C, rồi Clang biên
  dịch ARM64 khi build app; không cần JIT trên iPhone.
- Metal renderer và shader compiler được giữ cùng bộ host đã tích hợp. Không
  ghép renderer wgpu của PC vào iOS.
- Có launcher Việt/Anh, Story/Sandbox, điều khiển cảm ứng/controller, save
  import/export, cấu hình hình ảnh và multiplayer/voice từ source đã phục hồi.
- Multiplayer giữ protocol mở rộng của Mugoat; cần server tương thích. Kiểm
  thử UDP không thay thế kiểm thử gameplay iPhone ↔ PC trên server thật.
- `ModFiles`, `ModRuntime`, `RPFArchive` và UI quản lý mod có sẵn trong snapshot.
  **Chưa port tính năng add-on vehicle và sửa profile âm thanh V10 từ PC sang
  iOS.** Đây là công việc tiếp theo; không hứa mọi mod PC hoạt động.
- Bundle ID `vn.iosvn.mugoat.recovery`, tên app **Mugoat Rebuild**, version 2.1
  (21), cài riêng app cũ. Không tự chép/xóa save của app cũ.
- Đã bỏ patch cũ báo texture dictionary vắng mặt là "đã tải". Trạng thái tải
  thật được giữ nguyên. Data thiếu `MPShopSale` vẫn có thể chặn Los Santos
  Customs; bản này chưa bổ sung asset đó và không vượt điều kiện nhiệm vụ.

`UPSTREAMS.json` ghi commit của hai repo đang hoạt động đã tải để đối chiếu,
danh sách file giống/khác host mới và các packet ID chung. Host phục hồi có
ancestor `2cf36db9ed719c8233008a1efeb80e24f99b0b16`; **không phải merge toàn bộ
HEAD mới của hai repo**. Các patch C phụ thuộc function index của đúng engine,
nên cập nhật host mới phải làm riêng và kiểm chứng lại.

## Build không cần Mac cá nhân

Repo đích: https://github.com/BamBoo264/Mugoat-Ios (Private).

1. Source nằm ở `main`; các file đầu vào do chủ game cung cấp nằm trong
   `inputs/`. Workflow chỉ nhận repo Private, không tải game từ mirror công cộng.
2. Mở **Actions → Build Mugoat iOS Recovery IPA → Run workflow → main**.
3. Khi job xanh, tải artifact **Mugoat-iOS-Recovery-IPAs**.
4. Artifact gồm `Mugoat-Cert-Paid.ipa` (yêu cầu thêm quyền bộ nhớ) và
   `Mugoat-AppleID-Free.ipa` (không yêu cầu các quyền đó), kèm SHA256 và báo cáo
   xác thực ARM64/Metal/bundle. Ký bằng ESign với chứng chỉ của bạn. Quyền bộ nhớ
   thực tế phụ thuộc provisioning profile; tên file không tự cấp quyền RAM.
5. Sau khi cài, chọn/chép bộ data của bạn có `data/` và `b/8b0b5899ed/` vào
   vùng Files của app hoặc chọn thư mục tương thích. Backup save cũ trước khi
   nhập qua giao diện save. Không cần tải 20 GB data lên GitHub.

Build dùng macOS ARM64/Xcode trên GitHub và có thể tiêu tốn hạn mức Actions
của tài khoản. Không đặt chứng chỉ ESign, `.p12`, password hay profile ký vào repo.
Không có auto-publish release, token mã hóa riêng hoặc server của repo cũ.

## Chuẩn bị lại đầu vào trên PC

```powershell
python tools/prepare_inputs.py --mirror "C:\duong-dan\game" --out "C:\thu-muc-moi"
```

Script chỉ đọc game gốc, kiểm tra engine/index hash, nén shader packs và chia
file thành các phần 16 MiB. Chép thư mục `inputs` kết quả vào **repo Private**.
Nguồn game gốc và source PC V10 không bị sửa. Build chỉ cần khoảng 74 MB file
đầu vào của bộ data hiện có; không cần toàn bộ thư mục game.

## Kiểm tra

```text
cargo test --locked --manifest-path native-port/online-bridge/Cargo.toml --lib
python native-port/app/Tests/online_codegen.py
python -m unittest discover -s tests -v
```

Workflow thêm kiểm thử Swift/C/C++, build ARM64, chữ ký ad-hoc và cấu trúc
IPA. Job xanh **không chứng minh** FPS, nhiệt độ, Jetsam, nhiệm vụ cốt truyện,
camera/cutscene và multiplayer hoạt động đầy đủ trên iPhone 14 Pro Max; cần
chạy app thật để xác nhận.

## Giấy phép

Phần Muguet/networking theo GPL-3.0-or-later; host Port và các dependency giữ
giấy phép riêng. Xem `LICENSE`, `native-port/LICENSE`, `upstream-reference/`
và `native-port/app/Resources/Licenses/`. Không có data game trong gói source
offline; repo build Private có đầu vào riêng của người dùng.
