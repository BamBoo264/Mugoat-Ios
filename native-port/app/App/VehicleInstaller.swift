import Foundation

/// Installs validated DLCs or constructs an OPEN Legacy DLC from loose vehicle assets.
/// No original game archive is modified. Imports are staged and installed per package atomically.
enum VehicleInstaller {
    static let metadataTypes = ["vehicles.meta":"VEHICLE_METADATA_FILE", "handling.meta":"HANDLING_FILE",
        "carcols.meta":"CARCOLS_FILE", "carvariations.meta":"VEHICLE_VARIATION_FILE", "vehiclelayouts.meta":"VEHICLE_LAYOUTS_FILE"]
    static func word(_ b: Data, _ p: Int) -> UInt32 { b[p..<(p+4)].enumerated().reduce(0) { $0 | UInt32($1.element) << (8*$1.offset) } }
    static func pack(_ files: [String:Data]) throws -> Data {
        guard !files.isEmpty, files.count < 1024 else { throw ModError("Gói xe có quá nhiều tệp.") }
        var names=Data([0]), entries:[(String,Int,Data)]=[]
        for name in files.keys.sorted() {
            guard name.utf8.allSatisfy({ (97...122).contains($0)||(48...57).contains($0)||$0==95||$0==46 }) else { throw ModError("Tên asset không hợp lệ: \(name)") }
            let offset=names.count; names.append(Data(name.utf8));names.append(0);entries.append((name,offset,files[name]!))
        }
        while names.count%16 != 0 {names.append(0)}
        guard names.count<65536 else {throw ModError("Bảng tên RPF quá lớn.")}
        let count=files.count+1, start=(16+16*count+names.count+511)/512*512
        var out=Data(count:start)
        func put(_ p:Int,_ v:UInt32){for i in 0..<4 {out[p+i]=UInt8(truncatingIfNeeded:v >> (i*8))}}
        put(0,0x52504637);put(4,UInt32(count));put(8,UInt32(names.count));put(12,0x4e45504f)
        put(20,0x7fffff00);put(24,1);put(28,UInt32(files.count))
        out.replaceSubrange((16+count*16)..<(16+count*16+names.count),with:names)
        for (i,e) in entries.enumerated() {
            let data=e.2, at=32+i*16, block=out.count/512, resource=data.starts(with:Data("RSC7".utf8))
            guard !resource || (data.count>=16 && data.count<0xffffff) else {throw ModError("Asset \(e.0) vượt 16 MiB hoặc RSC7 không hợp lệ; cần tối ưu asset.")}
            put(at,UInt32(e.1) | (resource ? UInt32(data.count&0xffff)<<16 : 0))
            put(at+4,UInt32(block)<<8 | (resource ? 0x80000000|UInt32((data.count>>16)&0xff) : 0))
            put(at+8,resource ? word(data,8):UInt32(data.count));put(at+12,resource ? word(data,12):0)
            out.append(data);while out.count%512 != 0 {out.append(0)}
        }
        return out
    }
    static func files(in root: URL) throws -> [URL] {
        let fm=FileManager.default, keys:[URLResourceKey]=[.isSymbolicLinkKey,.isRegularFileKey,.isDirectoryKey,.fileSizeKey]
        guard let e=fm.enumerator(at:root,includingPropertiesForKeys:keys,options:[.skipsHiddenFiles]) else {throw ModError("Không đọc được thư mục mod.")}
        var result:[URL]=[];var total:Int64=0
        for case let u as URL in e {
            let v=try u.resourceValues(forKeys:Set(keys))
            guard v.isSymbolicLink != true else {throw ModError("Mod chứa symlink; không nhập.")}
            guard u.pathComponents.count-root.pathComponents.count<=12 else {throw ModError("Thư mục mod lồng quá sâu.")}
            if v.isRegularFile == true {total+=Int64(v.fileSize ?? 0);guard total<=1024*1024*1024,result.count<8192 else {throw ModError("Gói mod vượt giới hạn 1 GiB/8192 tệp.")};result.append(u)}
        }
        // Prefer a supplied Legacy variant when the author also ships Enhanced.
        if result.contains(where:{$0.pathComponents.contains(where:{$0.lowercased()=="legacy"})}) {
            result=result.filter{!$0.pathComponents.contains(where:{$0.lowercased()=="enhanced"})}
        }
        return result
    }
    static func loose(_ files: [URL], output: URL, baseModels: Set<String>) throws -> URL {
        var assets:[String:Data]=[:],meta:[String:Data]=[:]
        for u in files {
            let n=u.lastPathComponent.lowercased(),ext=u.pathExtension.lowercased()
            if ext=="yft" || ext=="ytd" {
                guard assets[n]==nil else {throw ModError("Trùng tên asset \(n). Chọn riêng một biến thể xe.")}
                let b=try Data(contentsOf:u,options:.mappedIfSafe)
                guard b.count>=16,b.count<0xffffff,b.starts(with:Data("RSC7".utf8)),word(b,4)==(ext=="yft" ? 162:13) else {throw ModError("\(n) không phải Legacy RSC7 hỗ trợ hoặc vượt 16 MiB.")}
                guard (((word(b,8)>>28)<<4)|(word(b,12)>>28))==word(b,4) else {throw ModError("Header/flags asset không khớp: \(n)")}
                assets[n]=b
            } else if metadataTypes[n] != nil {
                guard meta[n]==nil else {throw ModError("Trùng metadata \(n); chọn một phiên bản.")}
                let b=try Data(contentsOf:u);_ = try ModXML.read(b);meta[n]=b
            }
        }
        let models=Set(assets.keys.filter{$0.hasSuffix(".yft") && !$0.hasSuffix("_hi.yft")}.map{String($0.dropLast(4))})
        guard !models.isEmpty else {throw ModError("Không có DLC RPF hoặc cặp YFT/YTD xe Legacy trong thư mục.")}
        for m in models {guard assets[m+".ytd"] != nil else {throw ModError("Thiếu \(m).ytd")}}
        if let vehicles=meta["vehicles.meta"] {
            let declared=Set((try ModXML.read(vehicles).values["modelName"] ?? []).map{$0.lowercased()})
            guard models.isSubset(of:declared) else {throw ModError("Model YFT không được khai báo đủ trong vehicles.meta.")}
        } else {
            guard models.isSubset(of:baseModels) else {throw ModError("Xe add-on mới cần vehicles.meta, handling/meta đi kèm. File rời không tự tạo được thông số xe.")}
        }
        let joined=models.sorted().joined(separator:"_");var hash:UInt64=1469598103934665603
        for b in joined.utf8 {hash=(hash ^ UInt64(b)) &* 1099511628211}
        let id="mugoat_"+String(hash,radix:16),device="dlc_"+id,change=id+"_AUTOGEN"
        var root=meta;root["vehicles.rpf"]=try pack(assets)
        let setup="<?xml version=\"1.0\"?><SSetupData><deviceName>\(device)</deviceName><datFile>content.xml</datFile><timeStamp>01/01/2020 12:00:00 PM</timeStamp><nameHash>\(id)</nameHash><contentChangeSetGroups><Item><NameHash>GROUP_STARTUP</NameHash><ContentChangeSets><Item>\(change)</Item></ContentChangeSets></Item></contentChangeSetGroups><type>EXTRACONTENT_COMPAT_PACK</type><order value=\"1001\"/></SSetupData>"
        var items="",enable=""
        for n in root.keys.sorted() {let type=n=="vehicles.rpf" ? "RPF_FILE":metadataTypes[n]!
            let path="\(device):/\(n)";items+="<Item><filename>\(path)</filename><fileType>\(type)</fileType><locked value=\"false\"/><disabled value=\"true\"/><persistent value=\"true\"/><overlay value=\"true\"/></Item>";enable+="<Item>\(path)</Item>"}
        root["setup2.xml"]=Data(setup.utf8)
        root["content.xml"]=Data("<?xml version=\"1.0\"?><CDataFileMgr__ContentsOfDataFileXml><disabledFiles/><includedXmlFiles/><includedDataFiles/><dataFiles>\(items)</dataFiles><contentChangeSets><Item><changeSetName>\(change)</changeSetName><filesToEnable>\(enable)</filesToEnable></Item></contentChangeSets><patchFiles/></CDataFileMgr__ContentsOfDataFileXml>".utf8)
        let file=output.appendingPathComponent("dlc.rpf");try pack(root).write(to:file,options:.atomic);return file
    }
    static func install(_ source: URL, into mods: URL, baseModels: Set<String>) throws -> [String] {
        let fm=FileManager.default, stage=fm.temporaryDirectory.appendingPathComponent("vehicle-import-"+UUID().uuidString)
        try fm.createDirectory(at:stage,withIntermediateDirectories:true);defer{try? fm.removeItem(at:stage)}
        var isDir:ObjCBool=false;guard fm.fileExists(atPath:source.path,isDirectory:&isDir) else {throw ModError("Không tìm thấy nguồn mod.")}
        var candidates:[URL]=[]
        if !isDir.boolValue && source.pathExtension.lowercased()=="rpf" {candidates=[source]}
        else {
            let folder:URL
            if isDir.boolValue {folder=source}
            else {
                guard ModFiles.archiveExtensions.contains(source.pathExtension.lowercased()) else {throw ModError("Chọn folder/ZIP/RPF hoặc chọn cùng lúc YFT/YTD/meta.")}
                let extracted=stage.appendingPathComponent("unpacked");try fm.createDirectory(at:extracted,withIntermediateDirectories:true)
                guard gi_extract_archive(source.path,extracted.path)>0 else {throw ModError("Không giải nén được mod.")};folder=extracted
            }
            let all=try files(in:folder);candidates=all.filter{$0.lastPathComponent.lowercased()=="dlc.rpf"}
            if candidates.isEmpty {candidates=[try loose(all,output:stage,baseModels:baseModels)]}
        }
        let packs=try candidates.map{try ModPack(url:$0)}
        var names=Set<String>(),models=Set<String>();let updating=Set(packs.map(\.name))
        for p in ModRuntime.catalog(mods).packs where !updating.contains(p.name) {models.formUnion(p.models)}
        for p in packs {
            guard names.insert(p.name).inserted,models.isDisjoint(with:p.models) else {throw ModError("Xung đột tên gói/model: \(p.name). Tắt bản xe trùng trước.")}
            models.formUnion(p.models)
        }
        return try packs.map {p in let installed=try ModRuntime.importPack(p.url,into:mods);return installed.name+": "+installed.vehicleModels.joined(separator:", ")}
    }
}
