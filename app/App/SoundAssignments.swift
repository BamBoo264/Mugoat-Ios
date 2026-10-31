import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
enum SoundAssignments {
 static var choices:[String:String] {
  get{UserDefaults.standard.dictionary(forKey:"NewGenSoundChoices") as? [String:String] ?? [:]}
  set{UserDefaults.standard.set(newValue,forKey:"NewGenSoundChoices")}
 }
 /// A raw sound-only DLC and its converted import must not both register one profile.
 static func resolveDuplicatePacks(log:(String)->Void){
  let imported=Set(SoundInstaller.available());guard !imported.isEmpty else{return}
  let fm=FileManager.default
  for mod in ModInstaller.installed() where mod.enabled {
   if fm.fileExists(atPath:mod.url.appendingPathComponent("sound-profiles.json").path){continue}
   var profiles=Set<String>(),vehicle=false,uncertain=false
   func scan(_ archive:RPFArchive,_ depth:Int){
    guard depth<5 else{uncertain=true;return}
    for e in archive.entries {
     if e.path.hasSuffix(".yft") || e.path.hasSuffix(".ytd") || e.path.hasSuffix("vehicles.meta"){vehicle=true}
     if e.path.hasSuffix(".rpf") {
      if let child=try? archive.nested(e){scan(child,depth+1)}else{uncertain=true}
     }else if e.path.hasSuffix("_game.dat151.rel") || e.path.hasSuffix("_game.dat151") {
      if let data=try? archive.binary(e),let names=try? ModAudio.profiles(data,filename:e.path.hasSuffix(".rel") ? e.path:e.path+".rel"){profiles.formUnion(names)}else{uncertain=true}
     }
    }
   }
   if let walk=fm.enumerator(at:mod.url,includingPropertiesForKeys:nil,options:.skipsHiddenFiles){
    for case let url as URL in walk where url.lastPathComponent.lowercased()=="dlc.rpf" {
     if let archive=try? RPFArchive(url:url){scan(archive,0)}else{uncertain=true}
    }
   }
   guard !vehicle,!uncertain,!profiles.isEmpty,profiles.isSubset(of:imported) else{continue}
   let off=URL(fileURLWithPath:mod.url.path+".off")
   guard !fm.fileExists(atPath:off.path) else{log("Sound conflict: duplicate backup already exists for \(mod.name); left unchanged.");continue}
   do{try fm.moveItem(at:mod.url,to:off);log("Sound conflict: disabled duplicate sound-only pack \(mod.name); converted import takes priority. Original kept as .off.")}
   catch{log("Sound conflict: \(error.localizedDescription)")}
  }
 }
 static func configure(){
  let available=Set(SoundInstaller.available());PGEnableSoundMods(!available.isEmpty)
  for (key,value) in choices where available.contains(value) {
   if let model=UInt32(key){_ = PGSelectVehicleSound(model,value)}
  }
 }
 static func set(_ model:UInt32,_ profile:String){
  var saved=choices
  if profile.isEmpty {saved.removeValue(forKey:String(model))}else{saved[String(model)]=profile}
  choices=saved;_ = PGSelectVehicleSound(model,profile)
 }
}
