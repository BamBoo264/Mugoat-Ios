# iOS 2.5 (25): hiệu năng và tiếng động cơ

## Đã triển khai

- Mặc định một lần khi nâng cấp: **Mượt 60**, 540p, cap 60 FPS. Potato: 432p và texture Lite. Chọn trong Cài đặt → Đồ họa & FPS → Chế độ hiệu năng. Tùy chỉnh/preset cũ vẫn có để hoàn tác.
- CLI và settings.xml dùng chung giá trị quality/LOD/density. Bản trước ghi ShadowQuality=1 và ReflectionQuality=1 vào XML ngay cả khi chọn preset thấp. Bản mới hạ bóng, phản chiếu, cỏ, hạt, tầm nhìn/LOD và mật độ ambient qua thiết lập engine; không xóa entity, không ép trời quang hay vượt điều kiện mission. ShaderQuality vẫn 1 vì bộ shader thấp hơn/cao hơn không đầy đủ cho bản này. Tắt FXAA/PostFX nặng trong chế độ hiệu năng.
- Độ phân giải động: lấy mẫu mỗi 2 giây, giảm một bậc sau ít nhất 3 mẫu FPS thấp/nóng; tối thiểu 15 giây giữa hai lần resize. Chỉ tăng lại sau 10 mẫu tốt và nhiệt nominal; sàn 360p. Bỏ qua loading, pause, cutscene và khi đang mở menu. Hiển thị độ phân giải thực cạnh FPS. FPS dưới 54 hoặc thermal serious/critical gây giảm; không tự đổi chất lượng giữa từng frame. Có thể không giúp bottleneck CPU; cần đo trên iPhone.
- Khôi phục API frame pacing vốn đang no-op: Metal present sau minimum duration tương ứng 60/30 FPS trên màn hình refresh cao; CADisplayLink cũng yêu cầu cadence đúng cap. Giảm thời gian đợi PSO chưa sẵn sàng từ 2 xuống 0,5 ms/frame ở chế độ hiệu năng; shader/pipeline vẫn compile nền và được cache như trước. Không sửa/fake GPU query/readback.
- Đọc asset local/mod dùng 4 FD gần nhất mỗi luồng I/O, eviction có giới hạn, pread song song không khóa toàn cục, đóng FD khi luồng kết thúc. Tránh open/close và phân giải đường dẫn ở mỗi lần đọc. Đây là overhead thấy được trong source; chưa có đo A/B chứng minh mức đóng góp vào stutter.
- Giữ importer ZIP/RPF/folder, sửa SH150/27rev, audio và cache persistent. Không cần viết lại importer. Asset game không bị sửa.

## Tiếng xe

- Trước đây mọi mô tô thiếu profile đều ưu tiên Faggio2. Nay phân biệt layout scooter: tay ga dùng Faggio/Sanchez, sport bike dùng Bati/Akuma.
- Trong Mod Manager, nút **ⓘ** cạnh xe mod cho chọn profile Bati/Akuma/Double-T/Daemon… lưu riêng từng model. Đổi khi đang lái được xử lý trên game thread ở lần kiểm tra tiếp theo (~250 ms); không chạy lại mỗi frame. Tự động khôi phục profile của mod nếu chọn Tự động. Profile được kiểm tra có tồn tại trước khi áp dụng.
- Đây là tiếng xe gốc có sẵn. Không thể tạo âm thanh Ducati thật từ model 3D; cần bộ audio tương thích. Không tăng gain toàn bộ mixer làm radio/môi trường quá lớn.

## Kiểm chứng và giới hạn

CI kiểm tra controller resolution (hitch đơn lẻ, pause/loading, hysteresis, cooldown, floor), giá trị CLI/XML nhất quán, đọc file đồng thời/eviction/EOF/error/cleanup, phân loại audio và thay override; tiếp tục test Metal archive, mod importer và toàn bộ Release. Chỉ tạo IPA Paid Cert có quyền RAM; bundle ID và pipeline compatibility identity giữ nguyên. Chưa đo FPS/1% low thực tế trên iPhone, không bảo đảm 60 FPS mọi cảnh hoặc model mod quá nặng. Mip Lite giảm chất lượng texture; giảm LOD sẽ có pop-in rõ hơn. Chuyển Tùy chỉnh để so sánh A/B, giữ cùng save/đường đi và trạng thái nhiệt.

## Cơ sở kỹ thuật

- Apple: [frame pacing qua afterMinimumDuration](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/FrameRate.html), [ProMotion cadence](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays).
- Apple: [giảm workload khi thermal serious](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum/serious), [tối ưu game Metal theo cả frame pacing và chất lượng](https://developer.apple.com/documentation/metal/improving-your-games-graphics-performance-and-settings).
- Giữ cách submit query hiện tại: log cũ cho thấy hàng chục CB query/frame nhưng chưa có A/B trên máy thật chứng minh batching khác tốt hơn. Không đổi đồng bộ GPU chỉ dựa vào GPU utilization thấp.
