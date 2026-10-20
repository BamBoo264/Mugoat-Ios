import Foundation

/// Installs validated DLCs or constructs an OPEN Legacy DLC from loose vehicle assets.
/// No original game archive is modified. Imports are staged and installed per package atomically.
enum VehicleInstaller {
    static let metadataTypes = ["vehicles.meta":"VEHICLE_METADATA_FILE", "handling.meta":"HANDLING_FILE",
        "carcols.meta":"CARCOLS_FILE", "carvariations.meta":"VEHICLE_VARIATION_FILE", "vehiclelayouts.meta":"VEHICLE_LAYOUTS_FILE"]
    static func cleanXML(_ data: Data) throws -> Data {
        guard let text=String(data:data,encoding:.utf8) else {throw ModError("Metadata không phải UTF-8.")}
        return Data(text.replacingOccurrences(of:"<!--[\\s\\S]*?-->",with:"",options:.regularExpression).utf8)
    }
    // Same vehicle-only adaptation as PC: original geometry/texture bytes are unchanged.
    static func compatible(_ source:URL, output:URL, gameData:URL?) throws -> URL {
        let original=try RPFArchive(url:source)
        var payload:[String:Data]=[:],total=0,hasAudio=false
        func unpack(_ r:RPFArchive,_ depth:Int) throws {
            guard depth<=4 else {throw ModError("RPF lồng quá sâu.")}
            for e in r.entries {
                let name=(e.path as NSString).lastPathComponent
                if name.hasSuffix(".awc") || name.hasSuffix(".rel") {hasAudio=true}
                if name.hasSuffix(".rpf") {try unpack(r.nested(e),depth+1)}
                else if name.hasSuffix(".yft") || name.hasSuffix(".ytd") || metadataTypes[name] != nil || name=="setup2.xml" {
                    guard payload[name]==nil else {throw ModError("Trùng asset/metadata: \(name)")}
                    let data=e.resourceVersion == nil ? try cleanXML(r.metadata(e)):r.bytes.subdata(in:e.offset..<(e.offset+e.size))
                    total+=data.count;guard total<=512*1024*1024 else {throw ModError("Mod giải nén vượt 512 MiB.")};payload[name]=data
                }
            }
        }
        try unpack(original,0)
        guard let vehicles=payload["vehicles.meta"] else {return hasAudio ? try soundPack(source,output:output):source}
        let baseURL=gameData?.appendingPathComponent("common/data/levels/gta5/vehicles.meta")
        guard let baseURL,let baseData=try? Data(contentsOf:baseURL) else {throw ModError("Chọn thư mục dữ liệu game trước khi nhập DLC xe để kiểm tra tương thích.")}
        let base=try ModXML.read(baseData)
        var known=Set((base.values["parent"] ?? [])+(base.values["residentTxd"] ?? [])+(base.values["txdName"] ?? []));known.insert("vehshare")
        known.formUnion(payload.keys.filter{$0.hasSuffix(".ytd")}.map{String($0.dropLast(4))})
        var xml=String(data:vehicles,encoding:.utf8)!
        let re=try NSRegularExpression(pattern:"<parent>\\s*([^<]+)\\s*</parent>")
        for m in re.matches(in:xml,range:NSRange(xml.startIndex...,in:xml)).reversed() {
            let parent=(xml as NSString).substring(with:m.range(at:1)).trimmingCharacters(in:.whitespacesAndNewlines)
            if !known.contains(parent) {xml=(xml as NSString).replacingCharacters(in:m.range,with:"<parent>vehshare</parent>")}
        }
        payload["vehicles.meta"]=Data(xml.utf8)
        // Stock layout definitions shipped by PC DLCs must not override the port's layout table.
        if payload["vehiclelayouts.meta"] != nil {
            let layouts=try String(contentsOf:gameData!.appendingPathComponent("common/data/ai/vehiclelayouts.meta"),encoding:.utf8).lowercased()
            for name in try ModXML.read(vehicles).values["layout"] ?? [] {guard layouts.contains(">"+name.lowercased()+"<") else {throw ModError("Layout tùy chỉnh chưa hỗ trợ: \(name)")}}
            payload.removeValue(forKey:"vehiclelayouts.meta")
        }
        if hasAudio {
            // Rebuild the original directory/mount layout, rather than flattening away
            // audio banks, REL metadata and their content.xml mount declarations.
            func rebuild(_ r:RPFArchive,_ depth:Int) throws -> Data {
                guard depth<=4 else {throw ModError("RPF lồng quá sâu.")}
                var files:[String:Data]=[:]
                for e in r.entries {
                    if e.path.hasSuffix(".rpf") {files[e.path]=try rebuild(r.nested(e),depth+1)}
                    else if (e.path as NSString).lastPathComponent=="vehicles.meta" {files[e.path]=payload["vehicles.meta"]}
                    else if e.resourceVersion != nil {files[e.path]=r.bytes.subdata(in:e.offset..<(e.offset+e.size))}
                    else {files[e.path]=try r.binary(e)}
                }
                return try pack(files)
            }
            let file=output.appendingPathComponent("dlc.rpf")
            try rebuild(original,0).write(to:file,options:.atomic)
            return file
        }
        let setup=try payload["setup2.xml"].map{try ModXML.read($0)}
        let name=setup?.values["deviceName"]?.first.map{String($0.lowercased().dropFirst(4))}
        guard let name,ModPack.validName(name),setup?.values["deviceName"]?.first?.lowercased().hasPrefix("dlc_")==true else {throw ModError("DLC thiếu tên thiết bị hợp lệ.")}
        let looseFolder=output.appendingPathComponent("loose-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:looseFolder,withIntermediateDirectories:true)
        for (n,b) in payload where n != "setup2.xml" {try b.write(to:looseFolder.appendingPathComponent(n))}
        return try loose(try files(in:looseFolder),output:output,baseModels:[],packName:name)
    }
    static func word(_ b: Data, _ p: Int) -> UInt32 { b[p..<(p+4)].enumerated().reduce(0) { $0 | UInt32($1.element) << (8*$1.offset) } }
    static func pack(_ files: [String:Data]) throws -> Data {
        guard !files.isEmpty, files.count < 1024, files.keys.allSatisfy({!$0.hasPrefix("/") && !$0.hasSuffix("/") && !$0.contains("//") && !$0.split(separator:"/").contains(where:{$0=="." || $0==".."})}) else { throw ModError("Gói xe có quá nhiều tệp.") }
        for path in files.keys {var parent=(path as NSString).deletingLastPathComponent;while !parent.isEmpty {guard files[parent]==nil else {throw ModError("File/thư mục trùng đường dẫn.")};parent=(parent as NSString).deletingLastPathComponent}}
        // Breadth-first table: each directory owns a contiguous range of children.
        var paths=[""], childRanges:[Int:Range<Int>]=[:]
        var cursor=0
        while cursor<paths.count {
            let parent=paths[cursor],prefix=parent.isEmpty ? "":parent+"/"
            if files[parent]==nil {
                let children=Set(files.keys.filter{$0.hasPrefix(prefix)}.map{String($0.dropFirst(prefix.count).split(separator:"/")[0])}).sorted()
                let start=paths.count
                paths += children.map{prefix+$0};childRanges[cursor]=start..<paths.count
            }
            cursor+=1
        }
        guard paths.count<8192 else {throw ModError("Quá nhiều mục RPF.")}
        var names=Data(),offsets:[Int]=[]
        for path in paths {
            let name=path.isEmpty ? "":(path as NSString).lastPathComponent
            guard name.utf8.allSatisfy({(97...122).contains($0)||(48...57).contains($0)||$0==95||$0==46||$0==45}),name != ".",name != ".." else {throw ModError("Tên asset không hợp lệ: \(name)")}
            offsets.append(names.count);names.append(Data(name.utf8));names.append(0)
        }
        while names.count%16 != 0 {names.append(0)}
        guard names.count<65536 else {throw ModError("Bảng tên RPF quá lớn.")}
        let count=paths.count,start=(16+16*count+names.count+511)/512*512
        var out=Data(count:start)
        func put(_ p:Int,_ v:UInt32){for i in 0..<4 {out[p+i]=UInt8(truncatingIfNeeded:v >> (i*8))}}
        put(0,0x52504637);put(4,UInt32(count));put(8,UInt32(names.count));put(12,0x4e45504f)
        out.replaceSubrange((16+count*16)..<(16+count*16+names.count),with:names)
        for (i,path) in paths.enumerated() {
            let at=16+i*16
            if let range=childRanges[i] {put(at,UInt32(offsets[i]));put(at+4,0x7fffff00);put(at+8,UInt32(range.lowerBound));put(at+12,UInt32(range.count));continue}
            let data=files[path]!,block=out.count/512,resource=data.starts(with:Data("RSC7".utf8))
            guard !resource || (data.count>=16 && data.count<0xffffff) else {throw ModError("Asset vượt 16 MiB hoặc RSC7 không hợp lệ: \(path)")}
            put(at,UInt32(offsets[i]) | (resource ? UInt32(data.count&0xffff)<<16:0))
            put(at+4,UInt32(block)<<8 | (resource ? 0x80000000|UInt32((data.count>>16)&0xff):0))
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
    static func loose(_ files: [URL], output: URL, baseModels: Set<String>, packName:String? = nil) throws -> URL {
        var assets:[String:Data]=[:],meta:[String:Data]=[:],audio:[String:Data]=[:]
        var audioMounts:[String:String]=[:]
        for u in files {
            let n=u.lastPathComponent.lowercased(),ext=u.pathExtension.lowercased()
            if ext=="yft" || ext=="ytd" {
                guard assets[n]==nil else {throw ModError("Trùng tên asset \(n). Chọn riêng một biến thể xe.")}
                let b=try Data(contentsOf:u,options:.mappedIfSafe)
                guard b.count>=16,b.count<0xffffff,b.starts(with:Data("RSC7".utf8)),word(b,4)==(ext=="yft" ? 162:13) else {throw ModError("\(n) không phải Legacy RSC7 hỗ trợ hoặc vượt 16 MiB.")}
                guard (((word(b,8)>>28)<<4)|(word(b,12)>>28))==word(b,4) else {throw ModError("Header/flags asset không khớp: \(n)")}
                assets[n]=b
            } else if ext=="rel" || ext=="awc" {
                let data=try Data(contentsOf:u,options:.mappedIfSafe)
                guard data.count>=8,data.count<=64*1024*1024 else {throw ModError("Audio bị cắt hoặc vượt 64 MiB: \(n)")}
                let path:String
                if ext=="awc" {
                    guard data.starts(with:Data("ADAT".utf8)) else {throw ModError("AWC không phải Legacy PC hỗ trợ: \(n)")}
                    let bank=u.deletingLastPathComponent().lastPathComponent.lowercased()
                    guard bank.hasPrefix("dlc_"),ModPack.validName(bank) else {throw ModError("Giữ AWC trong thư mục sfx/dlc_tên_gốc của tác giả, hoặc nhập DLC RPF chứa audio.")}
                    path="sfx/"+bank+"/"+n;audioMounts["sfx/"+bank]="AUDIO_WAVEPACK"
                } else {
                    let types:[String:(UInt32,String)]=[".dat151.rel":(151,"AUDIO_GAMEDATA"),".dat54.rel":(54,"AUDIO_SOUNDDATA"),".dat10.rel":(10,"AUDIO_SYNTHDATA")]
                    guard let suffix=types.keys.first(where:{n.hasSuffix($0)}),let type=types[suffix],word(data,0)==type.0 else {throw ModError("REL chưa hỗ trợ hoặc header không khớp: \(n)")}
                    path="audioconfig/"+n
                    let mounted="audioconfig/"+String(n.dropLast(suffix.count))+".dat"
                    audioMounts[mounted]=type.1
                }
                guard audio[path]==nil else {throw ModError("Trùng audio: \(path)")};audio[path]=data
            } else if metadataTypes[n] != nil {
                guard meta[n]==nil else {throw ModError("Trùng metadata \(n); chọn một phiên bản.")}
                let b=try cleanXML(Data(contentsOf:u));_ = try ModXML.read(b);meta[n]=b
            }
        }
        let fragments=Set(assets.keys.filter{$0.hasSuffix(".yft") && !$0.hasSuffix("_hi.yft")}.map{String($0.dropLast(4))})
        let models: Set<String>
        if let v=meta["vehicles.meta"] {models=Set(try ModXML.read(v).values["modelName"] ?? []);guard models.isSubset(of:fragments) else {throw ModError("Thiếu YFT cho model khai báo.")}}
        else {models=fragments}
        guard !models.isEmpty || (!audio.isEmpty && audioMounts.values.contains("AUDIO_GAMEDATA") && audioMounts.values.contains("AUDIO_WAVEPACK")) else {throw ModError("Không có xe Legacy hoặc bộ REL/AWC đầy đủ.")}
        for m in models {guard assets[m+".ytd"] != nil else {throw ModError("Thiếu \(m).ytd")}}
        if let vehicles=meta["vehicles.meta"] {
            let declared=Set((try ModXML.read(vehicles).values["modelName"] ?? []).map{$0.lowercased()})
            guard models.isSubset(of:declared) else {throw ModError("Model YFT không được khai báo đủ trong vehicles.meta.")}
        } else {
            guard models.isSubset(of:baseModels) else {throw ModError("Xe add-on mới cần vehicles.meta, handling/meta đi kèm. File rời không tự tạo được thông số xe.")}
        }
        let joined=(models.isEmpty ? audio.keys.sorted():models.sorted()).joined(separator:"_");var hash:UInt64=1469598103934665603
        for b in joined.utf8 {hash=(hash ^ UInt64(b)) &* 1099511628211}
        let id=packName ?? ("mugoat_"+String(hash,radix:16)),device="dlc_"+id,change=id+"_AUTOGEN"
        var root=meta;if !assets.isEmpty {root["vehicles.rpf"]=try pack(assets)}
        let setup="<?xml version=\"1.0\"?><SSetupData><deviceName>\(device)</deviceName><datFile>content.xml</datFile><timeStamp>01/01/2020 12:00:00 PM</timeStamp><nameHash>\(id)</nameHash><contentChangeSetGroups><Item><NameHash>GROUP_STARTUP</NameHash><ContentChangeSets><Item>\(change)</Item></ContentChangeSets></Item></contentChangeSetGroups><type>EXTRACONTENT_COMPAT_PACK</type><order value=\"1001\"/></SSetupData>"
        var items="",enable=""
        for n in root.keys.sorted() {let type=n=="vehicles.rpf" ? "RPF_FILE":metadataTypes[n]!
            let path="\(device):/\(n)";items+="<Item><filename>\(path)</filename><fileType>\(type)</fileType><locked value=\"false\"/><disabled value=\"true\"/><persistent value=\"true\"/><overlay value=\"true\"/></Item>";enable+="<Item>\(path)</Item>"}
        for (path,type) in audioMounts.sorted(by:{$0.key<$1.key}) {
            let mounted="\(device):/\(path)"
            items+="<Item><filename>\(mounted)</filename><fileType>\(type)</fileType><locked value=\"false\"/><disabled value=\"true\"/><persistent value=\"true\"/><overlay value=\"false\"/></Item>"
            enable+="<Item>\(mounted)</Item>"
        }
        for (path,data) in audio {
            root[path]=data
            if path.hasSuffix(".rel") {root[String(path.dropLast(4))]=data}
        }
        root["setup2.xml"]=Data(setup.utf8)
        root["content.xml"]=Data("<?xml version=\"1.0\"?><CDataFileMgr__ContentsOfDataFileXml><disabledFiles/><includedXmlFiles/><includedDataFiles/><dataFiles>\(items)</dataFiles><contentChangeSets><Item><changeSetName>\(change)</changeSetName><filesToEnable>\(enable)</filesToEnable></Item></contentChangeSets><patchFiles/></CDataFileMgr__ContentsOfDataFileXml>".utf8)
        let file=output.appendingPathComponent("dlc.rpf");try pack(root).write(to:file,options:.atomic);return file
    }
    static func soundPack(_ source:URL,output:URL) throws -> URL {
        let folder=output.appendingPathComponent("audio-only")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        func scan(_ r:RPFArchive,_ depth:Int) throws {
            guard depth<=4 else {throw ModError("Audio archive lồng quá sâu.")}
            for e in r.entries {
                if e.path.hasSuffix(".rpf"),let nested=try? r.nested(e) {try scan(nested,depth+1)}
                else if e.path.hasSuffix(".rel") || e.path.hasSuffix(".awc") {
                    let target=folder.appendingPathComponent(e.path)
                    guard !FileManager.default.fileExists(atPath:target.path) else {throw ModError("Trùng audio asset.")}
                    try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                    try r.binary(e).write(to:target)
                }
            }
        }
        try scan(RPFArchive(url:source),0)
        return try loose(files(in:folder),output:output,baseModels:[])
    }
    static func install(_ source: URL, into mods: URL, baseModels: Set<String>, gameData:URL? = nil,audioOnly:Bool = false) throws -> [String] {
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
        let packs=try candidates.map { candidate -> ModPack in
            let converted=stage.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at:converted,withIntermediateDirectories:true)
            return try ModPack(url:audioOnly ? soundPack(candidate,output:converted):(gameData == nil ? candidate:compatible(candidate,output:converted,gameData:gameData)))
        }
        var names=Set<String>(),models=Set<String>(),sounds=Set<String>();let updating=Set(packs.map(\.name))
        for p in ModRuntime.catalog(mods).packs where !updating.contains(p.name) {models.formUnion(p.models);sounds.formUnion(p.audioProfiles)}
        for p in packs {
            guard names.insert(p.name).inserted,models.isDisjoint(with:p.models) else {throw ModError("Xung đột tên gói/model: \(p.name). Tắt bản xe trùng trước.")}
            guard sounds.isDisjoint(with:p.audioProfiles) else {throw ModError("Trùng audio profile; tắt bộ âm thanh cũ trước.")}
            sounds.formUnion(p.audioProfiles);models.formUnion(p.models)
        }
        return try packs.map {p in let installed=try ModRuntime.importPack(p.url,into:mods);return installed.name+": "+(installed.vehicleModels+installed.audioProfiles.map{"âm thanh "+$0}).joined(separator:", ")}
    }
}
