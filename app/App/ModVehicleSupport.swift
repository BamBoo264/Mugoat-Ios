import Foundation
/// Only mod metadata is inspected, before engine startup. No model/texture conversion.
enum ModVehicleSupport {
 static func vehicles()->[String] {
  ModInstaller.installed().filter{$0.enabled}.flatMap{mod -> [String] in
   guard let b=try? Data(contentsOf:mod.url.appendingPathComponent(".mulone-vehicles.json")),let v=try? JSONSerialization.jsonObject(with:b) as? [String] else{return []}
   return v.filter{ModPack.validName($0)}
  }.sorted()
 }
 /// Fix an author-template placeholder only when its directory has one real archive.
 /// Ambiguous references are retained; no geometry, texture or handling is changed.
 static func repairContentMounts(_ text:String,paths:[String],log:(String)->Void)->String {
  let re=try! NSRegularExpression(pattern:"[A-Za-z0-9_]+:/[^<\\s\"']+\\.rpf",options:.caseInsensitive)
  var result=text
  let source=text as NSString,known=Set(paths.map{$0.lowercased()})
  for m in re.matches(in:text,range:NSRange(location:0,length:source.length)).reversed() {
   let uri=source.substring(with:m.range)
   guard let colon=uri.range(of:":/") else{continue}
   let relative=String(uri[colon.upperBound...]).replacingOccurrences(of:"%PLATFORM%",with:"x64",options:.caseInsensitive).lowercased()
   guard !known.contains(relative),(relative as NSString).lastPathComponent=="vehicle_mods.rpf" else{continue}
   let parent=(relative as NSString).deletingLastPathComponent
   let candidates=paths.filter{($0.lowercased() as NSString).deletingLastPathComponent==parent && $0.lowercased().hasSuffix("_mods.rpf")}
   guard candidates.count==1 else{log("Vehicle compatibility: ambiguous/missing mount \(uri); unchanged.");continue}
   let oldName=(uri as NSString).lastPathComponent,newName=(candidates[0] as NSString).lastPathComponent
   let fixed=String(uri.dropLast(oldName.count))+newName
   result=(result as NSString).replacingCharacters(in:m.range,with:fixed)
   log("Vehicle compatibility: archive mount \(uri) -> \(fixed).")
  }
  return result
 }
 static func prepare(manifestPath:String,log:(String)->Void) {
  let fm=FileManager.default
  guard let b=try? Data(contentsOf:URL(fileURLWithPath:manifestPath)),let manifest=try? JSONSerialization.jsonObject(with:b) as? [String:Any],let rows=manifest["files"] as? [[Any]] else{return}
  var known=Set(rows.compactMap{$0.first as? String}.filter{$0.lowercased().hasSuffix(".ytd")}.map{URL(fileURLWithPath:$0).deletingPathExtension().lastPathComponent.lowercased()})
  known.insert("vehshare")
  var archives:[(URL,RPFArchive,URL)]=[]
  var names:[URL:Set<String>]=[:]
  func textures(_ r:RPFArchive,_ depth:Int) {
   guard depth<5 else{return}
   for e in r.entries {
    if e.path.hasSuffix(".ytd"){known.insert(URL(fileURLWithPath:e.path).deletingPathExtension().lastPathComponent)}
    if e.path.hasSuffix(".rpf"),let child=try? r.nested(e){textures(child,depth+1)}
   }
  }
  let mods=ModInstaller.installed().filter{$0.enabled && !$0.name.hasPrefix("_newgen_story_") && !fm.fileExists(atPath:$0.url.appendingPathComponent("skin-models.json").path)}
  for mod in mods {
   guard let walk=fm.enumerator(at:mod.url,includingPropertiesForKeys:nil,options:.skipsHiddenFiles) else{continue}
   for case let url as URL in walk {
    if url.pathExtension.lowercased()=="yft" {
     var model=url.deletingPathExtension().lastPathComponent.lowercased();if model.hasSuffix("_hi"){model=String(model.dropLast(3))}
     if ModPack.validName(model){names[mod.url,default:[]].insert(model)}
    }
    guard url.lastPathComponent.lowercased()=="dlc.rpf" else{continue}
    do{let r=try RPFArchive(url:url);textures(r,0);archives.append((url,r,mod.url))}catch{log("Vehicle metadata scan: \(error.localizedDescription)")}
   }
  }
  // Virtual TXD relationships are providers too, even without a same-named YTD.
  let childRE=try! NSRegularExpression(pattern:"<child>\\s*([^<]+)\\s*</child>")
  func registerChildren(_ text:String) {
   let ns=text as NSString
   for m in childRE.matches(in:text,range:NSRange(location:0,length:ns.length)) {known.insert(ns.substring(with:m.range(at:1)).trimmingCharacters(in:.whitespacesAndNewlines).lowercased())}
  }
  let base=URL(fileURLWithPath:manifestPath).deletingLastPathComponent().appendingPathComponent("common/data/levels/gta5/vehicles.meta")
  if let text=try? String(contentsOf:base,encoding:.utf8){registerChildren(text)}
  for (_,archive,_) in archives {
   for e in archive.entries where e.path.hasSuffix("vehicles.meta") {
    if let data=try? archive.metadata(e),let text=String(data:data,encoding:.utf8){registerChildren(text)}
   }
  }
  let parentRE=try! NSRegularExpression(pattern:"<parent>\\s*([^<]+)\\s*</parent>")
  let modelRE=try! NSRegularExpression(pattern:"<modelName>\\s*([^<]+)\\s*</modelName>")
  for (url,r,root) in archives {
   do {
    var out=r.bytes,changed=false
    for e in r.entries where e.path.hasSuffix("vehicles.meta") || e.path.lowercased()=="content.xml" {
     let data=try r.metadata(e)
     guard var text=String(data:data,encoding:.utf8) else{continue}
     // Some PC packs use a long run of dashes as an XML comment. XML forbids
     // internal "--"; retain a valid separator without touching any game fields.
     text=text.replacingOccurrences(of:"<!-{3,}>",with:"<!-- separator -->",options:.regularExpression)
     if e.path.lowercased()=="content.xml" {text=repairContentMounts(text,paths:r.entries.map(\.path),log:log)}
     let ns=text as NSString
     for m in modelRE.matches(in:text,range:NSRange(location:0,length:ns.length)) {
      let name=ns.substring(with:m.range(at:1)).trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
      if ModPack.validName(name){names[root,default:[]].insert(name)}
     }
     for m in parentRE.matches(in:text,range:NSRange(location:0,length:ns.length)).reversed() {
      let parent=ns.substring(with:m.range(at:1)).trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
      // These absent stock-DLC parents occur in the supplied SH150/27rev packs.
      // Never replace an existing real or virtual provider; other unknown names are retained.
      if !known.contains(parent) {
       if parent=="vehicles_biker_shared" || parent=="vehicles_race_generic" {
        text=(text as NSString).replacingCharacters(in:m.range,with:"<parent>vehshare</parent>")
        log("Vehicle compatibility: missing texture parent \(parent) -> vehshare in \(url.lastPathComponent)/\(e.path).")
       }else{log("Vehicle compatibility: unresolved texture parent \(parent); kept unchanged.")}
      }
     }
     if text != String(data:data,encoding:.utf8) {
      // Append an uncompressed binary entry; all geometry, nested RPFs and flags stay byte-identical.
      let count=Int(VehicleInstaller.word(out,4)),nsStart=16+16*count
      let nameSize=Int(VehicleInstaller.word(out,8))
      var entryAt:Int?=nil
      for i in 0..<count {
       let at=16+i*16,a=VehicleInstaller.word(out,at),c=VehicleInstaller.word(out,at+4)
       if c==0x7fffff00{continue}
       let offset=Int((UInt64(a)|UInt64(c)<<32)>>40 & 0xffffff)*512
       if offset==e.offset {entryAt=at;break}
      }
      guard nsStart+nameSize<=out.count,let at=entryAt else{throw ModError("Không tìm thấy entry metadata.")}
      while out.count%512 != 0{out.append(0)}
      let block=out.count/512,new=Data(text.utf8)
      func put(_ at:Int,_ n:UInt32){for i in 0..<4{out[at+i]=UInt8(truncatingIfNeeded:n>>(i*8))}}
      put(at,VehicleInstaller.word(out,at)&0xffff);put(at+4,UInt32(block)<<8);put(at+8,UInt32(new.count));put(at+12,0)
      out.append(new);changed=true
     }
    }
    if changed {
     let backup=url.deletingLastPathComponent().appendingPathComponent(".dlc.rpf.mulone-original")
     if !fm.fileExists(atPath:backup.path){try fm.copyItem(at:url,to:backup)}
     try out.write(to:url,options:.atomic)
    }
   }catch{log("Vehicle compatibility: \(error.localizedDescription); original pack retained on write failure.")}
  }
  for mod in mods {
   do{try JSONSerialization.data(withJSONObject:Array(names[mod.url] ?? []).sorted()).write(to:mod.url.appendingPathComponent(".mulone-vehicles.json"),options:.atomic)}catch{log("Vehicle list: \(error.localizedDescription)")}
  }
 }
 /// Build a pre-boot index for RPF resources whose size uses OpenIV's 32-bit
 /// extended header. The pinned engine otherwise masks their length to24bits.
 static func prepareLargeResources(log:(String)->Void) {
  let fm=FileManager.default
  var index:[String:[String:UInt64]]=[:]
  do {
   for mod in ModInstaller.installed().filter({$0.enabled}) {
    guard let walk=fm.enumerator(at:mod.url,includingPropertiesForKeys:nil,options:.skipsHiddenFiles) else{continue}
    for case let url as URL in walk where url.lastPathComponent.lowercased()=="dlc.rpf" {
     let archive=try RPFArchive(url:url)
     let setup=archive.entries.first{$0.path=="setup2.xml"}
     let xml=try setup.map{try archive.metadata($0)}.flatMap{String(data:$0,encoding:.utf8)} ?? ""
     let re=try NSRegularExpression(pattern:"<deviceName>\\s*([^<]+)\\s*</deviceName>",options:.caseInsensitive)
     let ns=xml as NSString
     let device=re.firstMatch(in:xml,range:NSRange(location:0,length:ns.length)).map{ns.substring(with:$0.range(at:1)).lowercased()}
     let pack=url.deletingLastPathComponent().lastPathComponent.lowercased()
     func scan(_ a:RPFArchive,_ label:String,_ depth:Int)throws {
      guard depth<8 else{throw ModError("DLC lồng quá sâu.")}
      for e in a.entries {
       if e.path.hasSuffix(".rpf"),let device {
        try scan(a.nested(e),device+":/"+e.path,depth+1)
       } else if e.resourceVersion != nil && e.size>=0xffffff {
        guard e.size<=256*1024*1024 else{throw ModError("Resource vượt256MiB: \(e.path)")}
        // Verify a complete compressed payload once per scan. Keep bytes intact.
        _ = try ModResource.normalize(a.resourceData(e),name:e.path)
        let key=label.lowercased()+"|"+e.path.lowercased()
        let item:[String:UInt64]=["size":UInt64(e.size),"system":UInt64(e.unpacked),"graphics":UInt64(e.graphicsFlags)]
        if let old=index[key],old != item{throw ModError("Hai DLC dùng chung đường dẫn resource lớn: \(key)")}
        index[key]=item
       }
      }
     }
     try scan(archive,"x64/dlcpacks/"+pack+"/dlc.rpf",0)
    }
   }
   try fm.createDirectory(at:ModInstaller.modsFolder,withIntermediateDirectories:true)
   try JSONSerialization.data(withJSONObject:index,options:.sortedKeys).write(to:ModInstaller.modsFolder.appendingPathComponent(".newgen-resource32.json"),options:.atomic)
   log("Large mod resources: \(index.count) verified extended-size entries indexed before boot.")
  }catch {
   // A stale index must never be used for changed archives.
   try? Data("{}".utf8).write(to:ModInstaller.modsFolder.appendingPathComponent(".newgen-resource32.json"),options:.atomic)
   log("Large resource validation failed: \(error.localizedDescription). Extended-size resources are not enabled.")
  }
 }

}
