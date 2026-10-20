import Foundation
@main struct VehicleInstallerTests {
 static func tryNoAliases(_ r:RPFArchive)->Bool {try! ModAudio.nativeAliases(r)==nil}
 static func tryProfiles(_ b:Data,_ file:String)->[String] {try! ModAudio.profiles(b,filename:file)}
 static func main() throws {
  for name in ["ta103ninjah2r","brabus850","gt3flat6","w211"] {
   let file=name+"_game.dat151.rel"
   let data=try Data(contentsOf:URL(fileURLWithPath:"Tests/Fixtures/vehicle_audio/"+file))
   precondition(tryProfiles(data,file)==[name])
  }
  print("PASS: real H2R, Aquaphobic and W211 REL151 fixtures identify verified vehicle profiles")
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
  let audioSource=root.appendingPathComponent("audio-source");try fm.createDirectory(at:audioSource,withIntermediateDirectories:true)
  var audioRoot:[String:Data]=[:]
  for e in pack.archive.entries {audioRoot[e.path]=e.resourceVersion==nil ? try pack.archive.binary(e):pack.archive.bytes.subdata(in:e.offset..<(e.offset+e.size))}
  let awc=Data("ADATtest-bank-payload".utf8)
  func testREL(_ name:String)->Data {
   let words:[UInt32]=[151,8,0,3,4,0,1,ModAudio.hash(name),4,4,0,0]
   var b=Data();for w in words {for i in 0..<4 {b.append(UInt8(truncatingIfNeeded:w>>(i*8)))}};return b
  }
  let rel=testREL("custom")
  audioRoot["x64/audio/sfx/dlc_test/custom.awc"]=awc
  audioRoot["x64/audio/custom_game.dat151.rel"]=rel
  let audioDLC=audioSource.appendingPathComponent("dlc.rpf");try VehicleInstaller.pack(audioRoot).write(to:audioDLC)
  let audioOutput=root.appendingPathComponent("audio-output");try fm.createDirectory(at:audioOutput,withIntermediateDirectories:true)
  let converted=try VehicleInstaller.compatible(audioDLC,output:audioOutput,gameData:fakeGame)
  let retained=try RPFArchive(url:converted)
  for (path,data) in [("x64/audio/sfx/dlc_test/custom.awc",awc),("x64/audio/custom_game.dat151.rel",rel),("content.xml",audioRoot["content.xml"]!)] {
   let entry=retained.entries.first{$0.path==path}!;let actual=try retained.binary(entry);precondition(actual==data,"Audio and mount declarations must survive conversion")
  }
  do {_ = try VehicleInstaller.pack(["a":Data([1]),"a/b":Data([2])]);fatalError("File/directory collision accepted")}catch is ModError {}
  let audioFolder=a.appendingPathComponent("sfx/dlc_custom")
  try fm.createDirectory(at:audioFolder,withIntermediateDirectories:true)
  try awc.write(to:audioFolder.appendingPathComponent("custom.awc"))
  try rel.write(to:a.appendingPathComponent("custom_game.dat151.rel"))
  let looseAudioOut=root.appendingPathComponent("loose-audio");try fm.createDirectory(at:looseAudioOut,withIntermediateDirectories:true)
  let looseAudio=try RPFArchive(url:VehicleInstaller.loose(VehicleInstaller.files(in:a),output:looseAudioOut,baseModels:[]))
  let mountXML=String(data:try looseAudio.metadata(looseAudio.entries.first{$0.path=="content.xml"}!),encoding:.utf8)!
  precondition(mountXML.contains("AUDIO_GAMEDATA") && mountXML.contains("AUDIO_WAVEPACK") && mountXML.contains("/audioconfig/custom_game.dat</filename>"))
  precondition(looseAudio.entries.contains{$0.path=="sfx/dlc_custom/custom.awc"})
  try fm.removeItem(at:a.appendingPathComponent("sfx"));try fm.removeItem(at:a.appendingPathComponent("custom_game.dat151.rel"))
  // Reproduce the actual v26 failure: the guest opens .dat151, not .dat151.rel.
  let realGame=try Data(contentsOf:URL(fileURLWithPath:"Tests/Fixtures/vehicle_audio/ta103ninjah2r_game.dat151.rel"))
  let old=try RPFArchive(bytes:VehicleInstaller.pack(["audioconfig/ta103ninjah2r_game.dat151.rel":realGame,"audioconfig/test_sounds.dat54.rel":Data([54,0,0,0]),"audioconfig/test_amp.dat10.rel":Data([10,0,0,0])]))
  let fixed=try RPFArchive(bytes:ModAudio.nativeAliases(old)!)
  for path in ["audioconfig/ta103ninjah2r_game.dat151","audioconfig/test_sounds.dat54","audioconfig/test_amp.dat10"] {
   let plain=fixed.entries.first{$0.path==path}!,release=fixed.entries.first{$0.path==path+".rel"}!
   let left=try fixed.binary(plain),right=try fixed.binary(release);precondition(left==right)
  }
  precondition(tryNoAliases(fixed))
  let authorPlain=Data([54,0,0,0,9,8,7]),release=Data([54,0,0,0,1,2,3])
  let both=try RPFArchive(bytes:VehicleInstaller.pack(["audio/s.dat54":authorPlain,"audio/s.dat54.rel":release]))
  precondition(tryNoAliases(both),"Do not replace an author's existing native/plain data with its different release data")
  let nestedOnly=try RPFArchive(bytes:VehicleInstaller.pack(["audio.rpf":VehicleInstaller.pack(["game.dat151.rel":realGame])]))
  let fixedNested=try RPFArchive(bytes:ModAudio.nativeAliases(nestedOnly)!)
  let child=try fixedNested.nested(fixedNested.entries[0]);precondition(child.entries.contains{$0.path=="game.dat151"})
  print("PASS: native audio .dat151/.dat54/.dat10 lookups resolve; aliases byte identical; existing plain data preserved; nested archives; idempotent")
  let standalone=root.appendingPathComponent("standalone-sound"),soundOut=root.appendingPathComponent("sound-out")
  try fm.createDirectory(at:standalone.appendingPathComponent("sfx/dlc_custom"),withIntermediateDirectories:true)
  try fm.createDirectory(at:soundOut,withIntermediateDirectories:true)
  try awc.write(to:standalone.appendingPathComponent("sfx/dlc_custom/custom.awc"));try rel.write(to:standalone.appendingPathComponent("custom_game.dat151.rel"))
  let standaloneRPF=try VehicleInstaller.loose(VehicleInstaller.files(in:standalone),output:soundOut,baseModels:[])
  let sound=try ModPack(url:standaloneRPF)
  precondition(sound.models.isEmpty && sound.audioProfiles==["custom"])
  precondition(sound.archive.entries.contains{$0.path=="audioconfig/custom_game.dat151"})
  do {_ = try ModAudio.profiles(Data([151,0,0,0]),filename:"bad_game.dat151.rel");fatalError("Truncated REL accepted")}catch is ModError {}
  let extractedOut=root.appendingPathComponent("extracted-sound");try fm.createDirectory(at:extractedOut,withIntermediateDirectories:true)
  let extractedSound=try ModPack(url:VehicleInstaller.soundPack(standaloneRPF,output:extractedOut))
  precondition(extractedSound.audioProfiles==["custom"] && extractedSound.models.isEmpty)
  print("PASS: standalone sound DLC; REL type-3 profile hash verified; audio-only extraction; truncated REL rejected")
  print("PASS: RPF audio payloads/mount paths preserved; loose REL/AWC mounted; path collisions rejected")
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
  let legacySoundURL=root.appendingPathComponent("legacy-sound.rpf")
  var legacyFiles:[String:Data]=[:]
  for e in sound.archive.entries where !e.path.hasSuffix(".dat151") {legacyFiles[e.path]=try sound.archive.binary(e)}
  try VehicleInstaller.pack(legacyFiles).write(to:legacySoundURL)
  let legacyBefore=try Data(contentsOf:legacySoundURL),legacyMods=root.appendingPathComponent("legacy-mods")
  let installedLegacy=try ModRuntime.importPack(legacySoundURL,into:legacyMods)
  let (migratedManifest,_)=try ModRuntime.prepare(baseManifest:manifest,mods:legacyMods,runtime:root.appendingPathComponent("legacy-runtime"),dlcList:Data("<SMandatoryPacksData><Paths/></SMandatoryPacksData>".replacingOccurrences(of:"<Paths/>",with:"<Paths></Paths>").utf8))
  let migratedDocument=try JSONSerialization.jsonObject(with:Data(contentsOf:migratedManifest)) as! [String:Any]
  let migratedRoutes=migratedDocument["_mugoatOverrides"] as! [String:String]
  let migratedPath=migratedRoutes["x64/dlcPacks/"+installedLegacy.name+"/dlc.rpf"]!
  let migratedArchive=try RPFArchive(url:URL(fileURLWithPath:migratedPath))
  precondition(migratedArchive.entries.contains{$0.path=="audioconfig/custom_game.dat151"})
  let untouched=try Data(contentsOf:installedLegacy.url);precondition(untouched==legacyBefore)
  print("PASS: v26 sound pack repaired in runtime overlay without reinstall or changing original mod bytes")
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
