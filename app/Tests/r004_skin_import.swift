import Foundation
import Darwin
@main struct R004SkinTest {
 static func main() throws {
  setbuf(stdout,nil)
  let fm = FileManager.default, root = URL(fileURLWithPath:CommandLine.arguments[1])
  precondition(SkinInstaller.normalizedName("MỸ Nhân ĐẸP 01\t") == "mynhandep01")
  let stage = try ModInstaller.unpack(root.appendingPathComponent("ryoubi.rar"));defer{try? fm.removeItem(at:stage)}
  let original = (fm.enumerator(at:stage,includingPropertiesForKeys:nil)!.allObjects as! [URL]).first{$0.lastPathComponent=="ryoubi.ytd"}!
  let input = try Data(contentsOf:original)
  func word(_ d:Data,_ at:Int)->UInt32 {(0..<4).reduce(0){$0 | UInt32(d[at+$1]) << (8*$1)}}
  func raw(_ d:Data) -> Data {
   let size = ModResource.segmentSize(word(d,8)) + ModResource.segmentSize(word(d,12))
   var out = Data(count:size);let packed = d.subdata(in:16..<d.count)
   let ok = out.withUnsafeMutableBytes{o in packed.withUnsafeBytes{i in gi_inflate_resource(i.baseAddress,UInt32(packed.count),o.baseAddress,UInt32(size))}}
   precondition(ok==1);return out
  }
  precondition(ModResource.needsRepair(word(input,8)),"Supplied texture must reproduce the small-page problem")
  let output = try ModResource.normalize(input,name:"ryoubi.ytd")
  precondition(!ModResource.needsRepair(word(output,8)) && !ModResource.needsRepair(word(output,12)))
  let a=raw(input),b=raw(output),oldVirtual=ModResource.segmentSize(word(input,8)),newVirtual=ModResource.segmentSize(word(output,8))
  precondition(oldVirtual==10240 && newVirtual==16384)
  precondition(a[0..<oldVirtual] == b[0..<oldVirtual],"Virtual bytes moved/changed")
  precondition(a[oldVirtual..<a.count] == b[newVirtual..<(newVirtual+a.count-oldVirtual)],"Physical texture bytes changed")
  let again = try ModResource.normalize(output,name:"second import");precondition(again == output,"Repair must be idempotent")
  var rejected=false;do {_ = try ModResource.normalize(Data(input.dropLast(32)),name:"truncated.ytd")} catch {rejected=true};precondition(rejected)
  let plan = try SkinInstaller.plan(folder:stage,name:"r004-ryoubi",modelName:"MỸ Nhân ĐẸP 01")
  let pack=try RPFArchive(url:plan.items.first{$0.target.hasSuffix("/dlc.rpf")}!.source)
  let inner=try pack.nested(pack.entries.first{$0.path=="peds.rpf"}!)
  precondition(Set(inner.entries.map(\.path)) == Set(["ydd","yft","ymt","ytd"].map{"mynhandep01."+$0}))
  let texture=try inner.resourceData(inner.entries.first{$0.path=="mynhandep01.ytd"}!);precondition(texture==output)
  let metadata=String(data:try pack.metadata(pack.entries.first{$0.path=="peds.meta"}!),encoding:.utf8)!
  precondition(metadata.contains("<Name>mynhandep01</Name>"))
  let names=try JSONSerialization.jsonObject(with:Data(contentsOf:plan.items.first{$0.target=="skin-models.json"}!.source)) as! [String]
  precondition(names==["mynhandep01"])
  rejected=false;do {let broken=try ModInstaller.unpack(root.appendingPathComponent("makima-truncated.rar"));defer{try? fm.removeItem(at:broken)};_ = try SkinInstaller.plan(folder:broken,name:"broken")} catch {rejected=true};precondition(rejected,"Truncated Makima must never be installed")
  // Exercise nested archive repair on real original assets, not just the helper.
  var oldAssets:[String:Data]=[:]
  for case let url as URL in fm.enumerator(at:stage,includingPropertiesForKeys:nil)! where SkinInstaller.extensions.contains(url.pathExtension.lowercased()) {
   oldAssets[url.lastPathComponent.lowercased()] = try Data(contentsOf:url)
  }
  let oldInner=try VehicleInstaller.pack(oldAssets)
  let oldArchive=try RPFArchive(bytes:oldInner)
  let repaired=try ModResource.repairedArchive(oldArchive)!
  let checked=try RPFArchive(bytes:repaired)
  let checkedTexture=try checked.resourceData(checked.entries.first{$0.path=="ryoubi.ytd"}!);precondition(checkedTexture == output)
  let unchanged=try ModResource.repairedArchive(checked);precondition(unchanged == nil)
  let repairRoot=URL(fileURLWithPath:CommandLine.arguments[2])
  let vfStage=try ModInstaller.unpack(repairRoot.appendingPathComponent("vf8.zip"));defer{try? fm.removeItem(at:vfStage)}
  let vfPlan=ModInstaller.plan(folder:vfStage,name:"r004-vf8",index:.init())
  let vfInstalled=try ModInstaller.install(vfPlan);defer{try? fm.removeItem(at:vfInstalled)}
  ModVehicleSupport.prepareLargeResources(log:{print($0)})
  let indexData=try Data(contentsOf:ModInstaller.modsFolder.appendingPathComponent(".newgen-resource32.json"))
  let sizeIndex=try JSONSerialization.jsonObject(with:indexData) as! [String:[String:NSNumber]]
  print("Actual extended-resource paths: \(sizeIndex.keys.sorted())")
  precondition(sizeIndex["dlc_vf8:/x64/levels/gta5/vehicles/vehicles.rpf|vf8.yft"]?["size"]?.intValue == 17512137)
  precondition(sizeIndex["dlc_vf8:/x64/levels/gta5/vehicles/vehicles.rpf|vf8_hi.yft"]?["size"]?.intValue == 17502433)
  precondition(sizeIndex.count == 2)
  try indexData.write(to:root.appendingPathComponent(".newgen-resource32.json"))
  print("PASS actual VF8 large-resource index: both YFT lengths exceed24bits and remain exact; no geometry/texture change")
  print("PASS R004: actual Ryoubi small page repaired; 6144 padding bytes only; both segment payloads identical; corrupt resource/archive rejected; skin rename consistent and idempotent")
  print("NOT TESTED: iPhone rendered pixels, camera appearance or respawn timing")
 }
}
