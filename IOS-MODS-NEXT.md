# Điểm mở rộng mod xe sau bản phục hồi

Bản này giữ nguyên đường chạy iOS C/Metal. Không đưa `gpu.rs`, Wasmtime,
launcher WPF hoặc pipeline cache Vulkan của PC vào iOS.

Các điểm có sẵn để phát triển tiếp:

- `native-port/app/App/ModFiles.swift`, `ModManagerViewController.swift`:
  giao diện nhập/xóa mod và vùng file trong sandbox app.
- `ModRuntime.swift`, `RPFArchive.swift`: chuẩn bị overlay/catalog trước boot.
  `NativePortViewController.swift` truyền manifest overlay cho host.
- `CheatMenu.swift`: vị trí phù hợp để thêm danh sách/spawn model trên điện thoại.
- `Scripts/prepare_online_exports.py`, `prepare_online_c.py`: xuất typed native
  và gọi trên game thread. Không thêm import WASM làm lệch function index.
- `native-port/online-bridge`: FFI Rust ↔ C đã có kiểm tra kiểu và giới hạn RAM.

Khi chuyển tính năng từ PC V10, cần tách từng phần:

1. Kiểm tra import replace và add-on thật trên data rút gọn; quản lý overlay,
   backup và xung đột thay vì sửa archive gốc.
2. Đưa model catalog vào menu cảm ứng, gọi native spawn trên script thread;
   không dùng phím F6 hoặc file giao tiếp launcher Windows.
3. Chuyển chính sách audio fallback đã kiểm chứng ở PC: giữ profile hợp lệ,
   chỉ thay profile thiếu; xác minh typed native trên bản C trước khi gọi.
4. Kiểm tra resource PC Legacy, texture/LOD/shared dictionaries và giới hạn RAM
   của iPhone. Không tự coi asset Enhanced hoặc custom audio/ASI là tương thích.

Multiplayer không truyền toàn bộ model/texture cho máy khác. Những người chơi
muốn thấy cùng xe add-on phải có bộ asset tương thích và cùng spawn hash.
Giữ nguyên nhiệm vụ, collision và camera gốc; không ép hoàn thành nhiệm vụ
để che lỗi asset/streaming. Kiểm thử cả Story offline và multiplayer riêng.
