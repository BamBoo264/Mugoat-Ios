import UIKit
final class BundledMenyooViewController:UITableViewController {
 init(){super.init(style:.insetGrouped);title="Plugin Menyoo"}
 required init?(coder:NSCoder){fatalError()}
 override func tableView(_ tableView:UITableView,numberOfRowsInSection section:Int)->Int{1}
 override func tableView(_ tableView:UITableView,cellForRowAt indexPath:IndexPath)->UITableViewCell{
  let cell=UITableViewCell(style:.default,reuseIdentifier:nil);cell.textLabel?.text="Bật Menyoo tích hợp"
  let toggle=UISwitch();toggle.isOn=BundledMenyoo.enabled
  toggle.addAction(UIAction{action in guard let toggle=action.sender as? UISwitch else{return};UserDefaults.standard.set(toggle.isOn,forKey:"NewGenMenyooEnabled")},for:.valueChanged)
  cell.accessoryView=toggle;cell.selectionStyle = .none;return cell
 }
 override func tableView(_ tableView:UITableView,titleForFooterInSection section:Int)->String?{
  "Đã tích hợp plugin và bản dịch, không cần tải lại mod. Bật tại đây trước khi chơi. Trong game: Plugin → F8 để mở Menyoo, dùng bàn phím số để chọn. Ngôn ngữ mặc định của gói là Vietnamese; có thể chọn lại trong Settings → Language. Sau khi nhập skin ở Mods → Nhập skin addon, mở Tùy chọn người chơi → Đổi model → Skin addon NewGen; chọn tên như 2b hoặc a2 để mặc. Khởi động lại app sau khi thêm hoặc tắt skin. Menyoo mặc định tắt để giữ hành vi bản nền; không dùng đồng thời hai bản Menyoo."
 }
}
