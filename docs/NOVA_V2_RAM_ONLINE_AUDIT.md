# Nova Native Runtime V2 — RAM, cache và phòng Internet

## Log đã kiểm tra
Hai log V1 ở `E:\nova native log` của iPhone 14 Pro Max/A16. Giới hạn tiến trình ghi nhận 4096 MiB; không phải toàn bộ RAM vật lý.

## Đã xác nhận
- Bản cũ dùng ngưỡng dự phòng 384 MiB, thêm dải chặn tăng streaming 256 MiB: dưới 640 MiB có thể giảm tăng trưởng; dưới 384 MiB yêu cầu thu hồi. Đây là ngưỡng quản lý, không phải cấp phát một khối RAM bỏ trống.
- Hai log này đều ghi 0 lần clamp/eviction của guard; headroom khoảng 729–1715 MiB. Vì vậy không quy lỗi drop trong các log này cho guard.
- Footprint tăng khoảng 2380–3366 MiB. Chưa đủ bằng chứng để gọi là leak.
- Khi thermal chuyển serious, FPS thường xuống khoảng 22–41; lúc fair có nhiều mẫu 59–62. Đây là tương quan được log xác nhận, chưa xác định được hàm CPU/GPU nào gây nhiệt.
- Nhiều command buffer, có mẫu 30.7 buffer/frame và 25.6 idle-query buffer/frame. Chưa thay logic query/synchronization vì cần benchmark tránh phá renderer.
- Chỉ số GPU cũ thực chất là thời gian trung bình mỗi command buffer, không phải GPU frame time. Nhãn và chú thích đã sửa.
- Cùng container nhưng hai lần đều khởi tạo archive PSO mới, không có dòng xác nhận nạp archive cũ/lưu thành công. Đây là bằng chứng cache chưa được tái sử dụng ở những lần này; chưa chứng minh mọi stutter đều do shader.
- Không có lỗi giải mã texture, texture creation hoặc đọc file kéo dài được ghi nhận trong hai log. Không có OOM/trap được xác nhận trong đoạn log này.

## Thay đổi RAM
- Cho Nova thường bật thu hồi theo di chuyển, mặc định 80 m; có thể đổi/tắt trong RAM và streaming.
- Chỉ yêu cầu streamer gốc thu hồi asset không còn cần; không tự xóa nhà, xe, NPC hoặc entity nhiệm vụ. Engine vẫn quyết định asset còn được tham chiếu/pin.
- Auto theo giới hạn app: <=3 GiB:128 MiB; <=4.5 GiB:192 MiB; <=6 GiB:256 MiB; cao hơn:384 MiB. Giới hạn thêm dự phòng không quá khoảng 1/16 app cap.
- Với app cap 4096 MiB, auto dùng dự phòng192 MiB; mốc chủ động dọn1024 MiB. Di chuyển80m và headroom thấp mới đề nghị tối đa16MiB/lần, cách8giây. Không phải16MiB chắc chắn giải phóng được.
- Khi thiếu RAM nguy cấp hoặc nhận cảnh báo iOS, có thể dọn dù đang đứng yên. Không thể hứa chỉ dọn theo khoảng cách mà vẫn an toàn khi jetsam.
- Loading/respawn giữ guard gốc, tránh chu kỳ dọn mới làm chậm chuyển cảnh.
- Cài bằng ESign phải giữ entitlement; quyền increased-memory không bảo đảm app nhận toàn bộ RAM vật lý.

## Cache và chẩn đoán
- Đưa archive PSO ra khỏi lock pipeline, ghi trên queue riêng, coalesce, lưu tệp tạm rồi thay file cũ.
- Checkpoint sau30giây và định kỳ60giây, giữ flush khi ra nền.
- Log renderer CPU theo frame thực tế; mẫu CPU đầu tiên là n/a, không phải0.
- Giữ renderer, mặc định đồ họa, thuật toán synchronization và backend ARM64 AOT V1.

## Phòng online
- Sửa kết nối giả sau timeout, kiểm tra gói, giới hạn peer, relay host LAN, thread ownership, peer hết hạn và nhánh offline không chạy xử lý peer liên tục.
- Internet dùng TLS WebSocket + Cloudflare SQLite Durable Object mỗi phòng, không yêu cầu cùng Wi-Fi/mở port.
- Relay không lưu data game/save/chat; giới hạn16 kết nối,8KiB/gói,25gói/giây/socket, tự đóng socket rỗi.
- Đây là đồng bộ avatar thử nghiệm của Nova, chưa phải toàn bộ GTA Online; chưa có đồng bộ nhiệm vụ/damage/xe đầy đủ và chưa xác nhận crossplay GTAV-v10.1.
- Gói Free có quota; vượt quota có thể ngắt dịch vụ. Không đăng ký trả phí.

## Kiểm thử và giới hạn
Preflight commit b53594e: GitHub run42005411169 thành công. Swift iOS, renderer, importer xe/skin/audio, PAD/scaling, language reader, log/camera và UDP thật 1host2khách đã qua. Không phải kiểm thử gameplay trên iPhone.
Relay local qua Workers runtime thật: no-host, host collision,2khách ACK, chuyển state, giả sender, vector lỗi, leave/reconnect và host shutdown đã qua.
Client Internet bổ sung cần typecheck và kiểm tra production relay sau cấp quyền; V2 chưa build ở thời điểm ghi báo cáo.
Cần tester iPhone: chơi20–30phút, chuyển khu vực/lái nhanh, chết/qua nhiệm vụ, theo dõi texture/nhiệt, hai điện thoại khác mạng và host ra nền.

## Tham khảo chính thức
- https://developer.apple.com/documentation/os/os_proc_available_memory
- https://developer.apple.com/documentation/xcode/responding-to-low-memory-warnings
- https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit
- https://developers.cloudflare.com/durable-objects/platform/pricing/
- https://developers.cloudflare.com/durable-objects/examples/websocket-hibernation-server/

Các port khác có source kiểm chứng dùng giới hạn memory theo tiến trình, trả trang heap đã rảnh cho OS, nén texture, cache và pooling. Không có source native v10.1 nên chưa thể khẳng định chính xác cách dọn của bản đó.
