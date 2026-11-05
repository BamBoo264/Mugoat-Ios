import UIKit

enum NovaMemorySettings {
 static let distances=[40,60,80,120,160],reserves=[0,128,192,256,384,512]
 static var enabled:Bool {get{UserDefaults.standard.object(forKey:"NovaMovementCleanup") as? Bool ?? true}set{UserDefaults.standard.set(newValue,forKey:"NovaMovementCleanup")}}
 static var distance:Int {get{let v=UserDefaults.standard.integer(forKey:"NovaCleanupMetres");return distances.contains(v) ? v:80}set{UserDefaults.standard.set(newValue,forKey:"NovaCleanupMetres")}}
 static var reserve:Int {get{let v=UserDefaults.standard.integer(forKey:"NovaCleanupReserveV2");return reserves.contains(v) ? v:0}set{UserDefaults.standard.set(newValue,forKey:"NovaCleanupReserveV2")}}
 static func automaticReserve(limit:Int)->Int{limit<=3072 ? 128:limit<=4608 ? 192:limit<=6144 ? 256:384}
 static func effectiveReserve(limit:Int)->Int{min(reserve==0 ? automaticReserve(limit:limit):reserve,max(64,(limit/256)*16))}
 static func apply(){let limit=DeviceTier.probe().memoryLimitMB;PGConfigureMovementCleanup(enabled,UInt32(distance),UInt32(effectiveReserve(limit:limit)))}
}
final class NovaMemoryViewController:UITableViewController {
 private var limit:Int{DeviceTier.probe().memoryLimitMB}
 init(){super.init(style:.insetGrouped);title="RAM và streaming"}
 required init?(coder:NSCoder){fatalError()}
 override func numberOfSections(in t:UITableView)->Int{3}
 override func tableView(_ t:UITableView,numberOfRowsInSection s:Int)->Int{s==0 ? 1:s==1 ? NovaMemorySettings.distances.count:NovaMemorySettings.reserves.count}
 override func tableView(_ t:UITableView,titleForHeaderInSection s:Int)->String?{["Thu hồi theo di chuyển","Khoảng cách từ lần dọn trước","Ngưỡng RAM dự phòng"][s]}
 override func tableView(_ t:UITableView,titleForFooterInSection s:Int)->String?{
  if s==0{return "Có trên mọi bản Nova, ưu tiên máy ít RAM. Engine thu hồi asset không còn cần ở khu đã đi xa, không ép xoá nhà, NPC, xe hay vật thể nhiệm vụ đang dùng. Chỉ dọn nhẹ khi bộ nhớ bắt đầu thấp; vẫn có bảo vệ khi đứng yên hoặc nhận cảnh báo RAM. Khi chuyển cảnh/respawn, dùng guard chuyển cảnh gốc để tránh kéo dài tải. Thay đổi áp dụng khi khởi động lại app."}
  if s==1{return "Mặc định 80 m, kiểm tra vị trí 4 lần/giây. Mỗi lượt yêu cầu tối đa 16 MiB, cách ít nhất 8 giây trong điều kiện thường. Không phải cứ đi 80 m là xoá toàn bộ khu cũ."}
  return "Hạn mức app hiện tại: \(limit) MiB. Ngưỡng có hiệu lực: \(NovaMemorySettings.effectiveReserve(limit:limit)) MiB. Tự động theo hạn mức: ≤3 GiB: 128; ≤4,5 GiB: 192; ≤6 GiB: 256; cao hơn: 384 MiB. Mức chọn tay được giới hạn theo app để tránh giữ trống quá nhiều. Đây là ngưỡng phản ứng, không phải vùng RAM bị khoá riêng. Nếu tắt thu hồi theo di chuyển, guard gốc dùng 384 MiB dự phòng và biên tăng trưởng 256 MiB."
 }
 override func tableView(_ t:UITableView,cellForRowAt p:IndexPath)->UITableViewCell{
  let c=UITableViewCell(style:.default,reuseIdentifier:nil)
  if p.section==0 {c.textLabel?.text="Bật thu hồi theo di chuyển";let toggle=UISwitch();toggle.isOn=NovaMemorySettings.enabled;toggle.addAction(UIAction{a in if let v=a.sender as? UISwitch{NovaMemorySettings.enabled=v.isOn}},for:.valueChanged);c.accessoryView=toggle}
  else if p.section==1{let v=NovaMemorySettings.distances[p.row];c.textLabel?.text="\(v) m";c.accessoryType=v==NovaMemorySettings.distance ? .checkmark:.none}
  else{let v=NovaMemorySettings.reserves[p.row];c.textLabel?.text=v==0 ? "Tự động (khuyên dùng)":"\(v) MiB";c.accessoryType=v==NovaMemorySettings.reserve ? .checkmark:.none};return c
 }
 override func tableView(_ t:UITableView,didSelectRowAt p:IndexPath){if p.section==1{NovaMemorySettings.distance=NovaMemorySettings.distances[p.row]}else if p.section==2{NovaMemorySettings.reserve=NovaMemorySettings.reserves[p.row]};t.reloadData()}
}
