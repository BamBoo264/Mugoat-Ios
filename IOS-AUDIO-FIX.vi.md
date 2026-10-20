# iOS 2.3 (23) — âm thanh xe mod

Áp dụng cơ chế profile âm thanh của PC V10 vào native iOS, cùng game.wasm đã xác minh SHA256 `11ca8d2c04c5e843d18ff4aea4899d72c86973c6b031df334e67c446b2ae83e0`.

- Đọc model/audioNameHash/vehicleClass theo từng Item trong vehicles.meta, kể cả metadata trong RPF lồng. Xe đã cài được đọc lại khi khởi động, không cần nhập lại mod.
- Trên game thread, kiểm tra profile thực sự tồn tại qua audMetadataManager::GetObject_Verify, rồi gọi ForceVehicleEngineAudio. Giữ profile tác giả nếu có; nếu thiếu, chọn profile gốc cùng nhóm xe đã xác nhận tồn tại (mô tô: Faggio2/Sanchez; thể thao: TurismoR/Adder…). Nếu không có profile hợp lệ thì không ép profile tùy tiện.
- Áp dụng khi spawn và khi lên xe; theo dõi đổi xe mỗi 250 ms, không gọi lại liên tục mỗi frame. Chỉ áp dụng xe trong catalog mod ở offline, không sửa âm lượng chung hay metadata/asset gốc.
- Bổ sung hai export typed, giữ nguyên import/function indices. Cache Metal dùng lại revision tương thích của 2.2 vì renderer/shader không đổi.
- Build duy nhất Paid Cert, giữ bundle ID và entitlement RAM. Cài cập nhật bằng cùng chứng chỉ, đóng/mở app rồi gọi lại xe hoặc xuống/lên xe. Mod mới sau này tự dùng cùng cơ chế.
- Kiểm chứng: test parser nhiều xe/profile trống, chọn profile gốc/fallback, không chọn profile thiếu hoặc sai loại; CI Release và kiểm tra IPA. Chưa kiểm tra tiếng động cơ trực tiếp trên iPhone; tiếng fallback là tiếng xe gốc, không phải bộ âm thanh custom chưa được cung cấp.
