import Foundation
/// Optional script package; disabled by default so normal gameplay pays no interpreter cost.
enum BundledMenyoo {
 static let name="_newgen_menyoo"
 static var enabled:Bool {UserDefaults.standard.bool(forKey:"NewGenMenyooEnabled")}
 static func prepare() throws {
  let fm=FileManager.default,root=ModInstaller.modsFolder
  try fm.createDirectory(at:root,withIntermediateDirectories:true)
  let on=root.appendingPathComponent(name),off=root.appendingPathComponent(name+".off")
  var target=fm.fileExists(atPath:on.path) ? on:off
  if !fm.fileExists(atPath:target.path) {
   guard let zip=Bundle.main.url(forResource:"BundledMenyoo",withExtension:"zip") else{throw ModError("Thiếu gói Menyoo tích hợp.")}
   let stage=try ModInstaller.unpack(zip);defer{try? fm.removeItem(at:stage)}
   try "2".write(to:stage.appendingPathComponent(".newgen-menyoo"),atomically:true,encoding:.utf8)
   try fm.moveItem(at:stage,to:off);target=off
  }
  guard fm.fileExists(atPath:target.appendingPathComponent(".newgen-menyoo").path) else{throw ModError("Thư mục Menyoo không thuộc gói tích hợp; giữ nguyên.")}
  let marker=target.appendingPathComponent(".newgen-menyoo")
  if (try? String(contentsOf:marker,encoding:.utf8)) != "2" {
   guard let zip=Bundle.main.url(forResource:"BundledMenyoo",withExtension:"zip") else{throw ModError("Thiếu gói Menyoo tích hợp.")}
   let stage=try ModInstaller.unpack(zip);defer{try? fm.removeItem(at:stage)}
   let relative="menyooStuff/Language/Vietnamese.json"
   let data=try Data(contentsOf:stage.appendingPathComponent(relative))
   try data.write(to:target.appendingPathComponent(relative),options:.atomic)
   try "2".write(to:marker,atomically:true,encoding:.utf8)
  }
  let desired=enabled ? on:off
  if target != desired {
   guard !fm.fileExists(atPath:desired.path) else{throw ModError("Có hai bản Menyoo tích hợp; hãy giữ lại một bản trong Mods.")}
   try fm.moveItem(at:target,to:desired)
  }
 }
}
