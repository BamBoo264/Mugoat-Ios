import UIKit
final class NovaCameraViewController:UITableViewController {
 private var folder:URL? {
  for mod in ModInstaller.installed() where mod.enabled {
   let p=mod.url.appendingPathComponent("DynamicVehicleFirstPerson")
   if FileManager.default.fileExists(atPath:p.appendingPathComponent("settings_general.ini").path){
     let menuIni = p.appendingPathComponent("settings_menu.ini")
     if let content = try? String(contentsOf: menuIni, encoding: .utf8), content.contains("MenuKey = NONE") {
       try? update(menuIni, section: "MENU", key: "MenuKey", value: "F7")
     }
     return p
   }
  };return nil
 }
 init(){super.init(style:.insetGrouped);title="Camera góc nhìn thứ nhất"}
 required init?(coder:NSCoder){fatalError()}
 override func tableView(_ t:UITableView,numberOfRowsInSection s:Int)->Int{4}
 override func tableView(_ t:UITableView,cellForRowAt p:IndexPath)->UITableViewCell {
  let c=UITableViewCell(style:.subtitle,reuseIdentifier:nil)
  c.textLabel?.text=["Cách nhập mod camera", "Đặt phím mở menu thành F7", "Độ nhạy nhìn bằng cảm ứng / PAD", "Bật/tắt camera của plugin"][p.row]
  c.detailTextLabel?.text=folder == nil ? "Chưa tìm thấy DynamicVehicleFirstPerson đã bật":"Đã tìm thấy cấu hình plugin"
  c.detailTextLabel?.numberOfLines=0;return c
 }
 private func message(_ text:String){let a=UIAlertController(title:"Camera",message:text,preferredStyle:.alert);a.addAction(UIAlertAction(title:"Đóng",style:.cancel));present(a,animated:true)}
 override func tableView(_ t:UITableView,didSelectRowAt p:IndexPath){
  if p.row==0 {message("Dùng Quản lý mod trên màn hình chính để nhập ZIP DynamicVehicleFirstPerson gốc của bạn. Mod PC .asi chạy qua lớp tương thích, chưa được xác nhận hoạt động trên iPhone. Nếu bị lỗi hãy tắt riêng gói đó. FOV, độ nghiêng và quán tính nằm trong menu của plugin; dùng Plugin → F7 sau khi cấu hình. Không tích hợp sẵn gói ASI này vào IPA.");return}
  guard !ModInstaller.gameRunning else{message("Chỉnh trước khi vào game và khởi động lại app sau khi lưu.");return}
  guard let root=folder else{message("Nhập và bật ZIP gốc trước.");return}
  if p.row==1 {
   do{try update(root.appendingPathComponent("settings_menu.ini"),section:"MENU",key:"MenuKey",value:"F7");message("Đã đặt F7. Vào game, mở nút Plugin và chọn F7. Các phím mũi tên, Enter, Backspace dùng điều khiển menu.")}catch{message(error.localizedDescription)};return
  }
  if p.row==3 {
   let a=UIAlertController(title:"Camera plugin",message:"Áp dụng lần mở game tiếp theo.",preferredStyle:.alert)
   for enabled in [true,false]{a.addAction(UIAlertAction(title:enabled ? "Bật":"Tắt",style:.default){[weak self] _ in do{try self?.update(root.appendingPathComponent("settings_general.ini"),section:"Main",key:"Enable",value:enabled ? "true":"false")}catch{self?.message(error.localizedDescription)}})}
   a.addAction(UIAlertAction(title:"Huỷ",style:.cancel));present(a,animated:true);return
  }
  let a=UIAlertController(title:"Độ nhạy",message:"0,1–5. Áp dụng cho chuột/vuốt và PAD; không ép FOV mỗi frame.",preferredStyle:.alert)
  a.addTextField{$0.placeholder="Ví dụ: 1.0";$0.keyboardType = .decimalPad}
  a.addAction(UIAlertAction(title:"Lưu",style:.default){[weak self,weak a] _ in
   guard let self,let text=a?.textFields?.first?.text,let v=Double(text.replacingOccurrences(of:",",with:".")),v.isFinite,(0.1...5).contains(v) else{return}
   do{let f=root.appendingPathComponent("settings_general.ini");for s in ["Controls.Mouse","Controls.Gamepad"]{for k in ["SensitivityX","SensitivityY"]{try self.update(f,section:s,key:k,value:String(v))}}}catch{self.message(error.localizedDescription)}
  });a.addAction(UIAlertAction(title:"Huỷ",style:.cancel));present(a,animated:true)
 }
 private func update(_ url:URL,section:String,key:String,value:String)throws {
  let original=try String(contentsOf:url,encoding:.utf8)
  var lines=original.replacingOccurrences(of:"\r",with:"").components(separatedBy:"\n"),active=false,found=false
  for i in lines.indices {
   let line=lines[i].trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"\u{FEFF}",with:"")
   if line.hasPrefix("["){active=line.caseInsensitiveCompare("["+section+"]") == .orderedSame}
   if active,let eq=line.firstIndex(of:"="),line[..<eq].trimmingCharacters(in:.whitespaces).caseInsensitiveCompare(key) == .orderedSame {lines[i]=key+" = "+value;found=true}
  }
  guard found else{throw ModError("Không tìm thấy tuỳ chọn; giữ nguyên cấu hình.")}
  let backup=url.appendingPathExtension("nova-backup")
  if !FileManager.default.fileExists(atPath:backup.path){try original.write(to:backup,atomically:true,encoding:.utf8)}
  try lines.joined(separator:"\n").write(to:url,atomically:true,encoding:.utf8)
 }
}
