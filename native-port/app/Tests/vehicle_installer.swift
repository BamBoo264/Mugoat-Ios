import Foundation
@main struct VehicleInstallerTests {
 static func main() throws {
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("vehicle-tests-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:true);defer{try? fm.removeItem(at:root)}
  func resource(_ version:UInt32,_ count:Int)->Data {
   var b=Data(count:count);b.replaceSubrange(0..<4,with:Data("RSC7".utf8))
   for (at,v) in [(4,version),(8,(version>>4)<<28),(12,(version&15)<<28)] {for i in 0..<4 {b[at+i]=UInt8(truncatingIfNeeded:v>>(8*i))}}
   return b
  }
  func loose(_ name:String)->URL {
   let folder=root.appendingPathComponent(name);try! fm.createDirectory(at:folder,withIntermediateDirectories:true)
   try! resource(162,180001).write(to:folder.appendingPathComponent(name+".yft"))
   try! resource(13,1009).write(to:folder.appendingPathComponent(name+".ytd"))
   let xml="<CVehicleModelInfo__InitDataList><InitDatas><Item><modelName>\(name)</modelName><txdName>\(name)</txdName><audioNameHash>SANCHEZ</audioNameHash></Item></InitDatas><txdRelationships><Item><parent>vehshare</parent><child>\(name)</child></Item></txdRelationships></CVehicleModelInfo__InitDataList>"
   try! Data(xml.utf8).write(to:folder.appendingPathComponent("vehicles.meta"));return folder
  }
  let mods=root.appendingPathComponent("mods");try fm.createDirectory(at:mods,withIntermediateDirectories:true)
  let parsed=try ModXML.read(Data("<Root><InitDatas><Item><modelName>bike</modelName><audioNameHash/><vehicleClass>VC_MOTORCYCLE</vehicleClass></Item><Item><modelName>car</modelName><audioNameHash>ADDER</audioNameHash><vehicleClass>VC_SUPER</vehicleClass></Item></InitDatas></Root>".utf8))
  precondition(parsed.audioPolicies.count==2 && parsed.audioPolicies[0].profile=="bike" && parsed.audioPolicies[1].profile=="adder" && parsed.audioPolicies[0].kind=="vc_motorcycle")
  let scooter=try ModXML.read(Data("<r><InitDatas><Item><modelName>test</modelName><vehicleClass>VC_MOTORCYCLE</vehicleClass><layout>LAYOUT_BIKE_SCOOTER</layout></Item></InitDatas></r>".utf8))
  precondition(scooter.audioPolicies.first?.kind=="vc_motorcycle_scooter")
  let a=loose("testbike"),b=loose("otherbike")
  let legacy=try ModXML.read(Data("<r><!-- invalid -- legacy comment --><modelName>sh150</modelName></r>".utf8))
  precondition(legacy.values["modelName"]==["sh150"])
  let fakeGame=root.appendingPathComponent("game"),basePath=fakeGame.appendingPathComponent("common/data/levels/gta5")
  try fm.createDirectory(at:basePath,withIntermediateDirectories:true)
  try Data("<r><parent>vehshare</parent></r>".utf8).write(to:basePath.appendingPathComponent("vehicles.meta"))
  let sourceXML=try String(contentsOf:a.appendingPathComponent("vehicles.meta"),encoding:.utf8)
  try Data(sourceXML.replacingOccurrences(of:"vehshare",with:"vehicles_missing_dlc").utf8).write(to:a.appendingPathComponent("vehicles.meta"))
  try resource(162,1000).write(to:a.appendingPathComponent("testbike_exhaust.yft"))
  _ = try VehicleInstaller.install(a,into:mods,baseModels:[])
  _ = try VehicleInstaller.install(b,into:mods,baseModels:[])
  let catalog=ModRuntime.catalog(mods)
  precondition(catalog.problems.isEmpty && Set(catalog.vehicleModels)==["testbike","otherbike"],"Two bikes sharing vehshare must not conflict")
  let pack=catalog.packs.first{$0.vehicleModels==["testbike"]}!
  let adaptedMods=root.appendingPathComponent("adapted-mods")
  _ = try VehicleInstaller.install(pack.url,into:adaptedMods,baseModels:[],gameData:fakeGame)
  let adapted=ModRuntime.catalog(adaptedMods).packs.first{$0.vehicleModels==["testbike"]}!
  let adaptedXML=try adapted.archive.metadata(adapted.archive.entries.first{$0.path=="vehicles.meta"}!)
  precondition(String(data:adaptedXML,encoding:.utf8)!.contains("<parent>vehshare</parent>"))
  precondition(adapted.name==pack.name && adapted.vehicleModels==["testbike"])
  let nested=try pack.archive.nested(pack.archive.entries.first{$0.path=="vehicles.rpf"}!)
  let entry=nested.entries.first{$0.path=="testbike.yft"}!
  precondition(entry.size==180001 && entry.resourceVersion==162)
  precondition(nested.bytes.subdata(in:entry.offset..<(entry.offset+entry.size)) == resource(162,180001))
  let original=try Data(contentsOf:pack.url)
  _ = try VehicleInstaller.install(a,into:mods,baseModels:[])
  let reimported=try Data(contentsOf:pack.url)
  precondition(reimported==original,"Reimport must preserve payload bytes")
  let zip=root.appendingPathComponent("bike.zip"),process=Process()
  process.executableURL=URL(fileURLWithPath:"/usr/bin/ditto");process.arguments=["-c","-k","--keepParent",a.path,zip.path]
  try process.run();process.waitUntilExit();precondition(process.terminationStatus==0)
  _ = try VehicleInstaller.install(zip,into:mods,baseModels:[])
  let manifest=root.appendingPathComponent("manifest.json"),runtime=root.appendingPathComponent("runtime")
  let originalManifest=try JSONSerialization.data(withJSONObject:["files":[["common/data/dlcList.xml",123,0],["x64/unchanged.rpf",456,0]]])
  try originalManifest.write(to:manifest)
  let (overlay, mounted)=try ModRuntime.prepare(baseManifest:manifest,mods:mods,runtime:runtime,dlcList:Data("<SMandatoryPacksData><Paths><Item>platform:\\dlcPacks\\original\\</Item></Paths></SMandatoryPacksData>".utf8))
  let document=try JSONSerialization.jsonObject(with:Data(contentsOf:overlay)) as! [String:Any]
  let routes=document["_mugoatOverrides"] as! [String:String],rows=document["files"] as! [[Any]]
  precondition(mounted.packs.count==2 && rows[1][0] as? String == "x64/unchanged.rpf")
  precondition(routes.values.contains(pack.url.path),"Real manifest must route to installed RPF")
  let list=try String(contentsOf:URL(fileURLWithPath:routes["common/data/dlcList.xml"]!),encoding:.utf8)
  let unchanged=try Data(contentsOf:manifest)
  precondition(list.contains("original") && list.contains(pack.name) && unchanged==originalManifest)
  let unsafeZip=root.appendingPathComponent("unsafe.zip"),python=Process()
  python.executableURL=URL(fileURLWithPath:"/usr/bin/python3")
  python.arguments=["-c","import sys,zipfile; z=zipfile.ZipFile(sys.argv[1],'w'); z.writestr('../escape.meta','bad'); z.close()",unsafeZip.path]
  try python.run();python.waitUntilExit();precondition(python.terminationStatus==0)
  do {_ = try VehicleInstaller.install(unsafeZip,into:mods,baseModels:[]);fatalError("ZIP traversal accepted")}catch is ModError {}
  let replacement=root.appendingPathComponent("replacement");try fm.createDirectory(at:replacement,withIntermediateDirectories:true)
  try resource(162,1000).write(to:replacement.appendingPathComponent("pcj.yft"));try resource(13,1000).write(to:replacement.appendingPathComponent("pcj.ytd"))
  _ = try VehicleInstaller.install(replacement,into:mods,baseModels:["pcj"])
  do {_ = try VehicleInstaller.install(replacement,into:mods,baseModels:[]);fatalError("Unknown add-on without metadata accepted")}catch is ModError {}
  try fm.createSymbolicLink(at:a.appendingPathComponent("escape.yft"),withDestinationURL:URL(fileURLWithPath:"/etc/passwd"))
  do {_ = try VehicleInstaller.install(a,into:mods,baseModels:[]);fatalError("Symlink accepted")}catch is ModError {}
  let preserved=try Data(contentsOf:pack.url)
  precondition(preserved==original,"Rejected imports must preserve installed pack")
  print("PASS: actual installer folder/ZIP/RPF roundtrip, 24-bit resource sizes, shared TXD, update, metadata requirements and symlink rejection")
 }
}
