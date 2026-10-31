import Foundation
@main struct NovaModImportTests {
 static func main() throws {
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("nova-test-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:true);defer{try? fm.removeItem(at:root)}
  func words(_ values:[UInt32])->Data{var d=Data();for value in values{var v=value.littleEndian;withUnsafeBytes(of:&v){d.append(contentsOf:$0)}};return d}
  func resource(_ version:UInt32)throws->Data {
   let raw=Data(repeating:0x5a,count:16384);var packed=Data(count:17000)
   let size=packed.withUnsafeMutableBytes{o in raw.withUnsafeBytes{i in gi_deflate_raw(i.baseAddress,UInt32(raw.count),o.baseAddress,17000)}}
   precondition(size>0);packed.count=Int(size)
   return words([0x37435352,version,((version>>4)<<28)|(2<<17),(version&15)<<28])+packed
  }
  // Legacy replacement files through a real ZIP and the production planner.
  let car=root.appendingPathComponent("car");try fm.createDirectory(at:car,withIntermediateDirectories:true)
  for name in ["pcj.yft","pcj_hi.yft","pcj.ytd"]{try resource(name.hasSuffix("ytd") ? 13:162).write(to:car.appendingPathComponent(name))}
  let zip=root.appendingPathComponent("car.zip"),p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/ditto");p.arguments=["-c","-k","--keepParent",car.path,zip.path];try p.run();p.waitUntilExit();precondition(p.terminationStatus==0)
  let unpacked=try ModInstaller.unpack(zip);defer{try? fm.removeItem(at:unpacked)}
  var index=ModInstaller.GameIndex();for name in ["pcj.yft","pcj_hi.yft","pcj.ytd"]{index.byName[name]=["x64/levels/gta5/vehicles.rpf/"+name]}
  let plan=ModInstaller.plan(folder:unpacked,name:"Nova Synthetic Car",index:index)
  precondition(plan.items.count==3 && !plan.unsupported && !plan.items.contains{$0.target.contains(".pending")})
  let installed=try ModInstaller.install(plan);defer{try? fm.removeItem(at:installed)}
  precondition(ModVehicleSupport.vehicles().contains("pcj"),"Replacement must appear in mod vehicle and sound pickers")
  // The pack writer and actual parser must agree on binary and resource entries.
  let archiveURL=root.appendingPathComponent("dlc.rpf"),meta=Data("<root>metadata</root>".utf8),geometry=try resource(162)
  try VehicleInstaller.pack(["vehicles.meta":meta,"models/pcj.yft":geometry]).write(to:archiveURL)
  let archive=try RPFArchive(url:archiveURL)
  let binary=try archive.binary(archive.entries.first{$0.path=="vehicles.meta"}!);precondition(binary==meta)
  let roundtrip=try archive.resourceData(archive.entries.first{$0.path=="models/pcj.yft"}!);precondition(roundtrip==geometry)
  let normalized=try ModResource.normalize(geometry,name:"pcj.yft");precondition(normalized==geometry)
  do{_ = try ModResource.normalize(Data("broken".utf8),name:"broken.yft");fatalError("Truncated resource accepted")}catch{}
  // REL54 PC records get the 3-byte native alignment once, with original record bytes intact.
  var rel54=words([54,9,0]);rel54.append(contentsOf:[8,0x11,0x22,0x33,0x44]);rel54.append(words([4,0,1,0x12345678,4,5,0,0]))
  let native=try ModAudio.nativeSoundData(rel54);precondition(native.count==rel54.count+3 && VehicleInstaller.word(native,4)==12)
  precondition(Array(native[12..<20]) == [8,0,0,0,0x11,0x22,0x33,0x44])
  do{_ = try ModAudio.nativeSoundData(rel54.dropLast());fatalError("Truncated REL accepted")}catch{}
  // Profile lookup is model-specific, not a generic sound shared by all cars.
  var rel151=words([151,5,0]);rel151.append(3);rel151.append(words([4,0,1,ModAudio.hash("novaengine"),4,1]))
  let profiles=try ModAudio.profiles(rel151,filename:"novaengine_game.dat151.rel");precondition(profiles==["novaengine"])
  let other=try ModAudio.profiles(rel151,filename:"other_game.dat151.rel");precondition(other.isEmpty)
  // Arbitrary skin aliases become lower-case, accent/space free; a complete quartet is required.
  precondition(SkinInstaller.normalizedName("MỸ Nhân ĐẸP 01\t")=="mynhandep01")
  let skin=root.appendingPathComponent("skin");try fm.createDirectory(at:skin,withIntermediateDirectories:true)
  let versions:[(String,UInt32)]=[("ydd",165),("yft",162),("ymt",2),("ytd",13)]
  for (ext,version) in versions{try resource(version).write(to:skin.appendingPathComponent("source model."+ext))}
  let skinPlan=try SkinInstaller.plan(folder:skin,name:"Nova Synthetic Skin",modelName:"MỸ Nhân ĐẸP 01")
  precondition(skinPlan.items.count==2 && skinPlan.kinds.contains("skin-addon"))
  try fm.removeItem(at:skin.appendingPathComponent("source model.yft"))
  do{_ = try SkinInstaller.plan(folder:skin,name:"Nova Incomplete Skin",modelName:"incomplete");fatalError("Incomplete skin accepted")}catch{}
  puts("PASS production importer: ZIP replacement planning, RPF/resource roundtrip, malformed resource/REL rejection, native REL54 alignment, distinct sound profiles, skin alias and complete quartet.")
 }
}
