# iOS 2.2 (22): hiệu năng và nhập xe

Xuất phát từ `v2-fixed` tại `4f2324c`. Bản này giữ bundle ID để cập nhật bằng cùng chứng chỉ, giữ dữ liệu và save; chỉ đóng gói **Mugoat-Cert-Paid.ipa**. Chứng chỉ dùng để ký lại trong ESign phải cho phép các entitlement RAM; yêu cầu trong IPA không tự bảo đảm iOS cấp quyền.

## Kết luận từ log của máy thật

- Log mới có 7 cửa sổ FPS, từ 30,8 đến 48,7 FPS, trung vị 41,9. Đây không phải phép đo 1% low. File native-metrics cũ chỉ ghi WORLD_READY, không có frame-time.
- Có lỗi archive `missing 'vertex' stage` và `Nothing to serialize`. Source gọi serialize sau mỗi 300 command buffer và sau các lô nhỏ pipeline, ngay trên đường render. Nhiều lần ghi trong gameplay đã được log xác nhận.
- Prewarm cũ đọc 2.148 recipe, nhưng chỉ lấy shader function; recipe chứa ID layout/pass tạm, không đủ tái tạo PSO đầy đủ. Callback cũ giữ tham chiếu pass/layout có thể thay đổi hoặc bị hủy. Nhánh pending có thể vẽ bằng pipeline trước đó không tương thích.
- FPS vẫn thấp ở cửa sổ `compiling=0`. Vì vậy không thể quy toàn bộ lag cho shader. Có khoảng 55 command buffer truy vấn idle/frame, cần đo tiếp trên iPhone; bản này không thay đổi kết quả query hay giả trạng thái GPU đã hoàn tất.
- Cửa sổ health cuối không có đọc file chậm/lỗi, app khoảng 2,47 GB và còn headroom; chưa đủ chứng cứ kết luận RAM/SSD là nguyên nhân chính. Các log cấp phát quan sát được chủ yếu ở startup.
- Không có dòng ModRuntime chứng minh pack đã mount. Source cũ có thể chép file rồi báo cài xong mà engine không sử dụng. Engine iOS còn thiếu nhánh nhận marker OPEN mà đường mod PC đã có.

## Thay đổi

- `MRPipelineCache.*`: recipe đầy đủ (shader, vertex layout/stride, blend/write mask, attachment/depth/stencil/sample/topology); prewarm PSO thực trên một queue utility. Cache phân biệt GPU, iOS và revision. Archive đọc riêng với archive ghi, lưu atomic mỗi 30 giây hoặc khi vào background, không serialize trong commit render. Pipeline đã warm trả ngay, không chờ queue ghi file. Cache cũ thiếu dữ liệu được bỏ qua, không xóa dữ liệu game.
- `MRRenderer.mm`: ngân sách đợi pipeline tối đa khoảng 2 ms cho cả frame; pipeline chưa sẵn sàng tạm bỏ draw, không dùng pipeline vật liệu khác. Khôi phục khởi tạo texture dự phòng đúng kiểu. Giữ sửa texture/mip hiện tại. Sửa mẫu số thống kê GPU từ command buffer sang frame.
- `MRFrameReports.mm`: tổng hợp local mỗi 15 giây, ghi p95/p99/max, frame >50/100 ms, pipeline/GPU wait/submit, RAM và thermal vào `performance-latest.json`, `performance-windows.jsonl` trong Documents. File lịch sử giới hạn 2 MB, không upload mạng và không ghi từng frame.
- `NativeFiles.c`: phục hồi đường đọc chuẩn qua manifest; bỏ dò nhiều đường dẫn mod sai trên mỗi lần mở asset.
- `VehicleInstaller.swift`, `RPFArchive.swift`, `ModManagerViewController.swift`: nhập folder/ZIP/RPF hoặc chọn cùng YFT/YTD/meta; đóng gói loose Legacy thành DLC OPEN, kiểm tra model/metadata/version, báo lỗi thực thay vì chỉ chép file. Chia sẻ texture không còn bị hiểu là trùng model. Quét/nhập ngoài luồng UI; không sửa mod khi game đang chạy.
- `ManagedOpenRPF.c`, `prepare_online_*`, màn hình khởi động: nhận OPEN chỉ khi bật mod đã kiểm tra trong Story offline; khóa khi Online. Mọi key AES khác vẫn chạy thân decrypt gốc. Không thêm WASM import hay làm lệch function index. Không fake điều kiện mission/texture loaded.
- `GameInstallerShim.c`: giải nén mod vào staging riêng, từ chối đường dẫn thoát thư mục, link, file trùng, dữ liệu lỗi/cắt cụt; giới hạn dung lượng và số file. Không thay đổi importer bộ game lớn.

## Cách dùng

1. Ký lại IPA Paid Cert bằng ESign, giữ entitlement extra-memory/extended-virtual-addressing nếu chứng chỉ hỗ trợ. Cài cập nhật bằng cùng bundle ID/chứng chỉ; không xóa app cũ trước khi sao lưu save.
2. Trước khi vào game, mở Quản lý Mod → Nhập Mod từ tệp / thư mục. Chọn folder xe hoặc ZIP có `dlc.rpf`. Với xe file rời, chọn cả YFT/YTD và các metadata tác giả cung cấp. Add-on mới cần `vehicles.meta`; replacement cần tên xe gốc đọc được trong data.
3. Bật Story offline rồi vào game. Trong menu mod chọn model đã cài để gọi xe. Tắt/xóa pack rồi khởi động lại để hoàn tác; RPF gốc không bị sửa.
4. Lần đầu đi qua khu vực mới vẫn có thể compile pipeline chưa gặp. Lần sau cùng revision/GPU/iOS nạp archive và prewarm recipe đã học. Không thể suy ra mọi tổ hợp pipeline của cả game từ danh sách shader; không hứa cache một lần xóa hết stutter streaming.

## Giới hạn và kiểm chứng

- Hỗ trợ pack RPF7 OPEN/plain có asset **GTA V Legacy** phù hợp (YFT 162, YTD 13), metadata XML; không chạy ASI/.NET/Lua của GTA PC, không chuyển Enhanced, không tự tạo handling/metadata còn thiếu. Loose resource giới hạn dưới 16 MiB mỗi file; gói quá nặng vẫn có thể làm giảm FPS/RAM. Không bảo đảm mọi DLC PC hoạt động với bộ data rút gọn.
- CI kiểm tra ABI/network, engine memory, input/save, installer folder/ZIP/RPF và manifest overlay, dữ liệu resource được giữ nguyên, từ chối xung đột/đường dẫn nguy hiểm. Kiểm tra Metal PSO/archive thực chỉ chạy nếu runner có Metal device; nếu không sẽ báo SKIP rõ ràng, vẫn compile source Metal cache và toàn bộ Release.
- Chưa có phép đo A/B bản mới trên iPhone của người dùng. Không tuyên bố đạt 60 FPS hay đã hết lỗi mission. Cần cùng cấu hình/đoạn đường, một lượt cache lạnh rồi mở lại chạy lượt cache nóng; gửi hai file performance và native-port.log để xác định bottleneck còn lại.

## Rollback

Commit trước sửa là `4f2324c`; giữ toàn bộ lịch sử branch, không force-push. Cài IPA trước bằng cùng ID hoặc revert commit bản này. Cache v3 riêng với cache cũ. Sao lưu save trước mọi lần đổi phiên bản.
