import Foundation

/// Startup-only DLC audio import. REL54 conversion is identical to the tested
/// Mugoat converter; samples and wavepack directory names remain unchanged.
enum SoundInstaller {
 /// Route a sound-only DLC through REL conversion even when imported from the general Mods row.
 /// Keeping the raw PC DLC bypassed conversion and registered silent engine profiles on iOS.
 static func isSoundOnly(_ folder: URL) -> Bool {
  let fm=FileManager.default
  var audio=false,vehicle=false
  func scan(_ r:RPFArchive,_ depth:Int) {
   guard depth<5 else{return}
   for e in r.entries {
    if e.path.hasSuffix("vehicles.meta") || e.path.hasSuffix(".yft") || e.path.hasSuffix(".ydd"){vehicle=true}
    if e.path.hasSuffix(".dat54.rel"){audio=true}
    if e.path.hasSuffix(".rpf"),let child=try? r.nested(e){scan(child,depth+1)}
   }
  }
  if let walk=fm.enumerator(at:folder,includingPropertiesForKeys:nil) {
   for case let url as URL in walk {
    if url.pathExtension.lowercased()=="rpf",let r=try? RPFArchive(url:url){scan(r,0)}
    if url.lastPathComponent.lowercased().hasSuffix(".dat54.rel"){audio=true}
    if ["yft","ydd"].contains(url.pathExtension.lowercased()){vehicle=true}
   }
  }
  return audio && !vehicle
 }
 static func stage(_ urls:[URL]) throws -> URL {
  let fm=FileManager.default, stage=fm.temporaryDirectory.appendingPathComponent("sound-"+UUID().uuidString)
  try fm.createDirectory(at:stage,withIntermediateDirectories:true)
  do {
   for (i,url) in urls.enumerated() {
    let active=url.startAccessingSecurityScopedResource();defer{if active{url.stopAccessingSecurityScopedResource()}}
    let input=stage.appendingPathComponent("input_\(i)");try fm.createDirectory(at:input,withIntermediateDirectories:true)
    if ["zip","rar","oiv"].contains(url.pathExtension.lowercased()) {
     let copy=input.appendingPathComponent(url.deletingPathExtension().lastPathComponent+".zip")
     try fm.copyItem(at:url,to:copy)
     let unpacked=try ModInstaller.unpack(copy);defer{try? fm.removeItem(at:unpacked)}
     try fm.moveItem(at:unpacked,to:input.appendingPathComponent("files"));try fm.removeItem(at:copy)
    }else{try fm.copyItem(at:url,to:input.appendingPathComponent(url.lastPathComponent))}
   }
   return stage
  }catch{try? fm.removeItem(at:stage);throw error}
 }
 static func build(_ stage:URL) throws -> (ModInstaller.Plan,[String]) {
  let fm=FileManager.default
  var files:[String:Data]=[:], total=0
  func add(_ path:String,_ data:Data) throws {
   guard data.count<=64*1024*1024 else{throw ModError("Mỗi tệp audio tối đa 64 MiB.")}
   if let prior=files[path] {guard prior==data else{throw ModError("Gói chứa nhiều biến thể audio. Chọn riêng thư mục FiveM hoặc một OIV.")};return}
   total+=data.count;guard total<=256*1024*1024,files.count<512 else{throw ModError("Gói audio vượt giới hạn 256 MiB/512 tệp.")};files[path]=data
  }
  func collect(_ path:String,_ data:Data) throws {
   let n=(path as NSString).lastPathComponent.lowercased()
   if n.hasSuffix(".rel") {
    guard [".dat151.rel",".dat54.rel",".dat10.rel"].contains(where:{n.hasSuffix($0)}),data.count>=8 else{throw ModError("REL chưa hỗ trợ: \(n)")}
    let expected=n.hasSuffix(".dat151.rel") ? 151:n.hasSuffix(".dat54.rel") ? 54:10
    guard VehicleInstaller.word(data,0)==UInt32(expected) else{throw ModError("Header REL không khớp: \(n)")}
    try add("audioconfig/"+n,data)
   }else if n.hasSuffix(".awc") {
    guard data.count>=8,["ADAT","TADA"].contains(String(decoding:data.prefix(4),as:UTF8.self)) else{throw ModError("AWC hỏng hoặc không hỗ trợ.")}
    let parts=path.lowercased().replacingOccurrences(of:"\\",with:"/").split(separator:"/").map(String.init)
    let bank=parts.dropLast().last(where:{$0.hasPrefix("dlc_")}).map{($0 as NSString).deletingPathExtension}
    guard let bank,ModPack.validName(bank) else{throw ModError("Giữ thư mục sfx/dlc_tên_gốc chứa AWC; dùng ZIP/thư mục nếu chọn từng tệp làm mất tên bank.")}
    try add("sfx/"+bank+"/"+n,data)
   }
  }
  func archive(_ r:RPFArchive,_ depth:Int,_ prefix:String="") throws {
   guard depth<5 else{throw ModError("RPF lồng quá sâu.")}
   for e in r.entries {
    if e.path.hasSuffix(".rpf") {
     // A combined car/sound DLC can also contain encrypted vehicle and language
     // archives. Audio import must not open or modify those unrelated archives.
     let lower=e.path.lowercased(),leaf=(lower as NSString).lastPathComponent
     let audio=lower.hasPrefix("sfx/") || lower.contains("/sfx/") || lower.hasPrefix("audio/") || lower.contains("/audio/") || leaf.hasPrefix("dlc_")
     if audio {try archive(r.nested(e),depth+1,prefix+e.path+"/")}
    }
    else if e.path.hasSuffix(".awc") || e.path.hasSuffix(".rel"){try collect(prefix+e.path,r.binary(e))}
   }
  }
  var inputs:[URL]=[]
  if let walk=fm.enumerator(at:stage,includingPropertiesForKeys:[.isSymbolicLinkKey,.isRegularFileKey]) {
   for case let url as URL in walk {
    let info=try url.resourceValues(forKeys:[.isSymbolicLinkKey,.isRegularFileKey])
    guard info.isSymbolicLink != true else{throw ModError("Không nhập symlink.")}
    if info.isRegularFile==true {inputs.append(url)}
    guard inputs.count<=8192 else{throw ModError("Quá nhiều tệp trong gói.")}
   }
  }
  // Prefer the intact FiveM tree over duplicate Singleplayer/OIV variants.
  let five=inputs.filter{$0.path.lowercased().contains("fivem") && ["rel","awc"].contains($0.pathExtension.lowercased())}
  if !five.isEmpty {inputs=five}
  for url in inputs where ["rel","awc","rpf","oiv"].contains(url.pathExtension.lowercased()) {
   if url.pathExtension.lowercased()=="rpf" {try archive(RPFArchive(url:url),0)}
   else if url.pathExtension.lowercased()=="oiv" {
    let unpacked=try Self.stage([url]);defer{try? fm.removeItem(at:unpacked)}
    // One OIV inside a ZIP: unpack and gather its REL/AWC/RPF files.
    if let walk=fm.enumerator(at:unpacked,includingPropertiesForKeys:nil){for case let item as URL in walk {
     if item.pathExtension.lowercased()=="rpf" {try archive(RPFArchive(url:item),0)}
     else if ["rel","awc"].contains(item.pathExtension.lowercased()){try collect(item.path,Data(contentsOf:item))}
    }}
   }else {try collect(url.path,Data(contentsOf:url))}
  }
  var profiles=Set<String>(),mounts:[String:String]=[:]
  for (path,data) in Array(files) {
   if path.hasSuffix(".rel") {
    let plain=String(path.dropLast(4));files[plain]=path.hasSuffix(".dat54.rel") ? try ModAudio.nativeSoundData(data):data
    let suffix=path.hasSuffix(".dat151.rel") ? "151":path.hasSuffix(".dat54.rel") ? "54":"10"
    mounts[String(plain.dropLast(suffix.count))]=suffix=="151" ? "AUDIO_GAMEDATA":suffix=="54" ? "AUDIO_SOUNDDATA":"AUDIO_SYNTHDATA"
    if suffix=="151" {profiles.formUnion(try ModAudio.profiles(data,filename:path))}
   }else if path.hasSuffix(".awc"){mounts[(path as NSString).deletingLastPathComponent]="AUDIO_WAVEPACK"}
  }
  guard !profiles.isEmpty,mounts.values.contains("AUDIO_SOUNDDATA"),mounts.values.contains("AUDIO_WAVEPACK") else{throw ModError("Cần bộ REL151 + REL54 + AWC đầy đủ và profile động cơ hợp lệ. Chọn cả ZIP/thư mục để giữ cấu trúc bank.")}
  var hash:UInt64=1469598103934665603;for c in files.keys.sorted().joined(separator:"_").utf8{hash=(hash ^ UInt64(c)) &* 1099511628211}
  let name="sound_"+String(hash,radix:16),device="dlc_"+name,change=name+"_STARTUP"
  let entries=mounts.sorted{$0.key<$1.key}.map{"<Item><filename>\(device):/\($0.key)</filename><fileType>\($0.value)</fileType><locked value=\"false\"/><disabled value=\"true\"/><persistent value=\"true\"/><overlay value=\"false\"/></Item>"}.joined()
  let enable=mounts.keys.sorted().map{"<Item>\(device):/\($0)</Item>"}.joined()
  files["setup2.xml"]=Data("<SSetupData><deviceName>\(device)</deviceName><datFile>content.xml</datFile><nameHash>\(name)</nameHash><contentChangeSetGroups><Item><NameHash>GROUP_STARTUP</NameHash><ContentChangeSets><Item>\(change)</Item></ContentChangeSets></Item></contentChangeSetGroups><type>EXTRACONTENT_COMPAT_PACK</type><order value=\"1001\"/></SSetupData>".utf8)
  files["content.xml"]=Data("<CDataFileMgr__ContentsOfDataFileXml><disabledFiles/><includedXmlFiles/><includedDataFiles/><dataFiles>\(entries)</dataFiles><contentChangeSets><Item><changeSetName>\(change)</changeSetName><filesToEnable>\(enable)</filesToEnable></Item></contentChangeSets><patchFiles/></CDataFileMgr__ContentsOfDataFileXml>".utf8)
  let pack=stage.appendingPathComponent("dlc.rpf");try VehicleInstaller.pack(files).write(to:pack,options:.atomic)
  let list=stage.appendingPathComponent("profiles.json");try JSONSerialization.data(withJSONObject:Array(profiles).sorted()).write(to:list)
  var plan=ModInstaller.Plan(name:name);plan.kinds.insert("audio")
  plan.items=[.init(source:pack,target:"update/x64/dlcpacks/\(name)/dlc.rpf",note:"Âm thanh động cơ"),.init(source:list,target:"sound-profiles.json",note:"Danh sách profile")]
  return (plan,Array(profiles).sorted())
 }
 static func available() -> [String] {
  ModInstaller.installed().filter{$0.enabled}.flatMap{mod -> [String] in
   guard let data=try? Data(contentsOf:mod.url.appendingPathComponent("sound-profiles.json")),let values=try? JSONSerialization.jsonObject(with:data) as? [String] else{return []};return values.filter{ModPack.validName($0)}
  }.sorted()
 }
}
