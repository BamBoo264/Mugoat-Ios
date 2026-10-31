import UIKit
/// Spatial reconstruction, not temporal frame generation. Changes apply at next start.
enum NovaUpscaling {
 static let titles=["Tắt — độ phân giải gốc", "Chất lượng — 85%", "Cân bằng — 67%", "Hiệu năng — 50%"]
 static var mode:Int { get{min(3,max(0,UserDefaults.standard.integer(forKey:"NovaUpscaler")))} set{UserDefaults.standard.set(min(3,max(0,newValue)),forKey:"NovaUpscaler")} }
 static func renderSize(width:Int,height:Int,mode:Int)->(Int,Int){
  guard (1...3).contains(mode) else{return(width,height)}
  let ratio=[1.0,0.85,0.67,0.5][mode]
  let factor=max(ratio,360.0/Double(max(360,height)))
  return(max(2,Int((Double(width)*factor).rounded()) & ~1),max(2,Int((Double(height)*factor).rounded()) & ~1))
 }
}
final class NovaUpscalingViewController:UITableViewController {
 init(){super.init(style:.insetGrouped);title="Nova Super Resolution"}
 required init?(coder:NSCoder){fatalError()}
 override func tableView(_ t:UITableView,numberOfRowsInSection s:Int)->Int{NovaUpscaling.titles.count}
 override func tableView(_ t:UITableView,cellForRowAt p:IndexPath)->UITableViewCell{
  let c=UITableViewCell(style:.default,reuseIdentifier:nil);c.textLabel?.text=NovaUpscaling.titles[p.row];c.accessoryType=NovaUpscaling.mode==p.row ? .checkmark:.none;return c
 }
 override func tableView(_ t:UITableView,didSelectRowAt p:IndexPath){NovaUpscaling.mode=p.row;t.reloadData()}
 override func tableView(_ t:UITableView,titleForFooterInSection s:Int)->String?{"Áp dụng ở lần mở game tiếp theo. Render thấp hơn rồi nâng ảnh bằng MetalFX. Có thể tăng FPS khi nghẽn GPU; không tạo khung hình giả, không khắc phục nghẽn CPU. Nếu thiết bị không hỗ trợ, game dùng cách phóng ảnh gốc. Độ phân giải trong Đồ hoạ là đầu ra mong muốn; tối thiểu 360p khi render."}
}
