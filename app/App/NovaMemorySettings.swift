import UIKit
enum NovaMemorySettings {
 static let distances=[40,60,80,120,160],reserves=[64,128,192,256]
 static var enabled:Bool {get{UserDefaults.standard.object(forKey:"NovaMovementCleanup") as? Bool ?? true}set{UserDefaults.standard.set(newValue,forKey:"NovaMovementCleanup")}}
 static var distance:Int {get{let v=UserDefaults.standard.integer(forKey:"NovaCleanupMetres");return distances.contains(v) ? v:80}set{UserDefaults.standard.set(newValue,forKey:"NovaCleanupMetres")}}
 static var reserve:Int {get{let v=UserDefaults.standard.integer(forKey:"NovaCleanupReserve");return reserves.contains(v) ? v:128}set{UserDefaults.standard.set(newValue,forKey:"NovaCleanupReserve")}}
 static func apply(){PGConfigureMovementCleanup(Theme.isLite && enabled,UInt32(distance),UInt32(reserve))}
}
final class NovaMemoryViewController:UITableViewController {
 init(){super.init(style:.insetGrouped);title="RAM • máy 4 GB"}
 required init?(coder:NSCoder){fatalError()}
 override func numberOfSections(in t:UITableView)->Int{3}
 override func tableView(_ t:UITableView,numberOfRowsInSection s:Int)->Int{s==0 ? 1:s==1 ? NovaMemorySettings.distances.count:NovaMemorySettings.reserves.count}
 override func tableView(_ t:UITableView,titleForHeaderInSection s:Int)->String?{["Thu hồi theo di chuyển","Khoảng cách từ vị trí dọn trước","RAM dự phòng"][s]}
 override func tableView(_ t:UITableView,titleForFooterInSection s:Int)->String?{
  s==0 ? "Dùng cho bản LowRAM, máy 4 GB. Áp dụng ở lần mở app tiếp theo. Đi đủ khoảng cách sẽ cho phép engine dọn asset không còn cần khi thiếu RAM. Vẫn bảo vệ khẩn cấp khi bộ nhớ quá thấp; không cưỡng bức xoá nhà, xe hay vật thể nhiệm vụ.":s==1 ? "Mặc định 80 m, không cộng thêm 160 m. Quá ngắn có thể khiến tải lại asset nhiều hơn.":"Mặc định 128 MiB. Đây là phần dự phòng trong hạn mức app thực tế, không phải RAM vật lý. Quyền RAM mở rộng còn phụ thuộc chứng chỉ ESign và iOS."
 }
 override func tableView(_ t:UITableView,cellForRowAt p:IndexPath)->UITableViewCell{
  let c=UITableViewCell(style:.default,reuseIdentifier:nil)
  if p.section==0 {c.textLabel?.text="Bật thu hồi theo di chuyển";let toggle=UISwitch();toggle.isOn=NovaMemorySettings.enabled;toggle.addAction(UIAction{a in if let v=a.sender as? UISwitch{NovaMemorySettings.enabled=v.isOn}},for:.valueChanged);c.accessoryView=toggle}
  else if p.section==1{let v=NovaMemorySettings.distances[p.row];c.textLabel?.text="\(v) m";c.accessoryType=v==NovaMemorySettings.distance ? .checkmark:.none}
  else{let v=NovaMemorySettings.reserves[p.row];c.textLabel?.text="\(v) MiB";c.accessoryType=v==NovaMemorySettings.reserve ? .checkmark:.none};return c
 }
 override func tableView(_ t:UITableView,didSelectRowAt p:IndexPath){if p.section==1{NovaMemorySettings.distance=NovaMemorySettings.distances[p.row]}else if p.section==2{NovaMemorySettings.reserve=NovaMemorySettings.reserves[p.row]};t.reloadData()}
}
