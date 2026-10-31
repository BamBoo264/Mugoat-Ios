import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct ModError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

/// Reads the open RPF7 table and XML metadata; geometry stays in the original archive.
/// Format reference: dexyfex/CodeWalker, RpfFile.cs (binary/resource entry layouts).
struct RPFArchive {
    struct Entry {
        let path: String
        let offset: Int
        let size: Int
        let unpacked: Int
        let encrypted: Bool
        let compressed: Bool
        let resourceVersion: Int?
        let graphicsFlags:UInt32
    }
    let bytes: Data
    let entries: [Entry]

    init(url: URL) throws { try self.init(bytes: Data(contentsOf: url, options: .mappedIfSafe)) }
    init(bytes: Data) throws {
        self.bytes = bytes
        func word(_ at: Int) throws -> UInt32 {
            guard at >= 0, at <= bytes.count - 4 else { throw ModError("RPF bị thiếu dữ liệu.") }
            return bytes[at..<(at + 4)].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
        }
        guard try word(0) == 0x52504637 else { throw ModError("Tệp không phải gói RPF7 của GTA V Legacy.") }
        let count = Int(try word(4)), namesSize = Int(try word(8))
        guard count > 0, count <= 100_000, namesSize > 0, namesSize <= 8 * 1024 * 1024,
              16 + count * 16 + namesSize <= bytes.count else { throw ModError("Bảng tệp RPF bị hỏng.") }
        guard try word(12) == 0x4e45504f || word(12) == 0 else { throw ModError("Bảng RPF đã mã hóa. Hãy xuất gói mở bằng OpenIV trước khi nhập.") }
        let namesStart = 16 + count * 16
        func name(_ offset: Int) throws -> String {
            guard offset >= 0, offset < namesSize else { throw ModError("Tên tệp RPF không hợp lệ.") }
            let tail = bytes[(namesStart + offset)..<(namesStart + namesSize)]
            guard let zero = tail.firstIndex(of: 0), let text = String(data: bytes[(namesStart + offset)..<zero], encoding: .utf8),
                  text.utf8.count <= 255, !text.contains("/"), !text.contains("\\"), text != ".", text != ".." else { throw ModError("Đường dẫn trong RPF không hợp lệ.") }
            return text.lowercased()
        }
        var output: [Entry] = [], visited = Set<Int>()
        func walk(_ index: Int, parent: String, depth: Int) throws {
            guard depth < 32, index >= 0, index < count, visited.insert(index).inserted else { throw ModError("Cấu trúc thư mục RPF bị hỏng hoặc lặp.") }
            let at = 16 + index * 16, first = try word(at), second = try word(at + 4)
            let directory = second == 0x7fffff00
            let text = try name(Int(directory ? first : first & 0xffff))
            guard index == 0 || !text.isEmpty else { throw ModError("Tệp RPF thiếu tên.") }
            let path = parent.isEmpty ? text : parent + "/" + text
            if directory {
                let start = Int(try word(at + 8)), length = Int(try word(at + 12))
                guard start <= count, length <= count - start else { throw ModError("Thư mục RPF vượt giới hạn.") }
                for child in start..<(start + length) { try walk(child, parent: path, depth: depth + 1) }
            } else {
                let resource = second & 0x80000000 != 0
                let packed = UInt64(first) | UInt64(second) << 32
                var size = Int(packed >> 16 & 0xffffff)
                let compressed = size != 0
                let offset = Int(packed >> 40 & (resource ? 0x7fffff : 0xffffff)) * 512
                let unpacked = Int(try word(at + 8)), flags = try word(at + 12)
                if resource && size == 0xffffff {
                    guard offset <= bytes.count - 16 else { throw ModError("Tài nguyên RPF bị cắt.") }
                    size = Int(bytes[offset + 7]) | Int(bytes[offset + 14]) << 8 | Int(bytes[offset + 5]) << 16 | Int(bytes[offset + 2]) << 24
                }
                if !resource && size == 0 { size = unpacked }
                guard offset >= namesStart + namesSize, size >= 0, offset <= bytes.count, size <= bytes.count - offset else { throw ModError("Dữ liệu tệp RPF vượt giới hạn.") }
                output.append(Entry(path: path, offset: offset, size: size, unpacked: unpacked,
                                    encrypted: !resource && flags != 0, compressed: compressed,
                                    resourceVersion: resource ? Int(((UInt32(unpacked) >> 28) << 4) | (flags >> 28)) : nil, graphicsFlags:flags))
            }
        }
        try walk(0, parent: "", depth: 0)
        guard visited.count == count, Set(output.map(\.path)).count == output.count else { throw ModError("Bảng RPF chứa mục mồ côi hoặc trùng tên.") }
        entries = output
    }

    func resourceData(_ entry:Entry) throws -> Data {
        guard let version=entry.resourceVersion,entry.size>=16 else {throw ModError("Không phải RSC7.")}
        var data=bytes.subdata(in:entry.offset..<(entry.offset+entry.size))
        // RPF large-resource headers borrow four bytes for the size. Restore a
        // canonical standalone RSC7 header from the authoritative entry flags.
        for (at,value) in [(0,UInt32(0x37435352)),(4,UInt32(version)),(8,UInt32(entry.unpacked)),(12,entry.graphicsFlags)] {
            for i in 0..<4 {data[at+i]=UInt8(truncatingIfNeeded:value>>(8*i))}
        };return data
    }
    func binary(_ entry:Entry) throws -> Data {
        guard entry.resourceVersion==nil,!entry.encrypted,entry.unpacked>0,entry.unpacked<=64*1024*1024 else {throw ModError("Audio/binary mã hóa hoặc vượt 64 MiB: \(entry.path)")}
        let data=bytes.subdata(in:entry.offset..<(entry.offset+entry.size))
        if !entry.compressed {return data}
        var out=Data(count:entry.unpacked)
        let valid=out.withUnsafeMutableBytes{o in data.withUnsafeBytes{i in gi_inflate_raw(i.baseAddress,UInt32(data.count),o.baseAddress,UInt32(entry.unpacked))}}
        guard valid==1 else {throw ModError("Binary nén bị hỏng: \(entry.path)")};return out
    }

    func metadata(_ entry: Entry) throws -> Data {
        guard entry.resourceVersion == nil, !entry.encrypted, entry.unpacked > 0,
              entry.unpacked <= 8 * 1024 * 1024 else { throw ModError("Metadata mod mã hóa hoặc quá lớn: \(entry.path)") }
        let data = bytes.subdata(in: entry.offset..<(entry.offset + entry.size))
        if !entry.compressed { return data }
        var result = Data(count: entry.unpacked)
        let valid = result.withUnsafeMutableBytes { out in data.withUnsafeBytes { input in
            gi_inflate_raw(input.baseAddress, UInt32(data.count), out.baseAddress, UInt32(entry.unpacked))
        } }
        guard valid == 1 else { throw ModError("Không giải nén được metadata: \(entry.path)") }
        return result
    }

    func nested(_ entry: Entry) throws -> RPFArchive {
        guard !entry.encrypted, entry.resourceVersion == nil, !entry.compressed else { throw ModError("RPF lồng đã mã hóa/nén: \(entry.path)") }
        return try RPFArchive(bytes: bytes.subdata(in: entry.offset..<(entry.offset + entry.size)))
    }
}


enum VehicleInstaller {
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
            var data=files[path]!
            let block=out.count/512,resource=data.starts(with:Data("RSC7".utf8))
            guard !resource || (data.count>=16 && data.count<=128*1024*1024) else {throw ModError("RSC7 bị cắt hoặc vượt 128 MiB: \(path)")}
            let sys=resource ? word(data,8):0,gfx=resource ? word(data,12):0
            let stored=resource ? min(data.count,0xffffff):0
            put(at,UInt32(offsets[i]) | (resource ? UInt32(stored&0xffff)<<16:0))
            put(at+4,UInt32(block)<<8 | (resource ? 0x80000000|UInt32((stored>>16)&0xff):0))
            put(at+8,resource ? sys:UInt32(data.count));put(at+12,resource ? gfx:0)
            if resource && data.count>=0xffffff {
                let n=UInt32(data.count)
                for (index,shift) in [(7,0),(14,8),(5,16),(2,24)] {data[index]=UInt8(truncatingIfNeeded:n>>shift)}
            }
            out.append(data);while out.count%512 != 0 {out.append(0)}
        }
        return out
    }
}
struct ModPack {static func validName(_ n:String)->Bool {!n.isEmpty && n.utf8.count<=63 && n.utf8.allSatisfy{(97...122).contains($0)||(48...57).contains($0)||$0==95}}}
enum ModAudio {
    static func nativeSoundData(_ b:Data) throws -> Data {
        func u(_ at:Int) throws -> Int {guard at>=0,at<=b.count-4 else {throw ModError("REL54 bị cắt.")};return Int(VehicleInstaller.word(b,at))}
        func append(_ n:Int,_ out:inout Data) {var v=UInt32(n).littleEndian;withUnsafeBytes(of:&v){out.append(contentsOf:$0)}}
        guard try u(0)==54 else {throw ModError("Không phải REL54.")}
        let length=try u(4), names=8+length, nameLength=try u(names), index=names+4+nameLength, count=try u(index)
        guard length>=4,count<=100000,count<=(b.count-index-4)/12 else {throw ModError("Index REL54 không hợp lệ.")}
        var rows:[(hash:Int,offset:Int,size:Int)]=[]
        for i in 0..<count {let a=index+4+i*12;rows.append((try u(a),try u(a+4),try u(a+8)))}
        let sorted=rows.sorted{$0.offset<$1.offset};var end=4
        for row in sorted {guard row.offset==end,row.size>=1,row.size<=length-row.offset else {throw ModError("REL54 có record chồng lấn/khoảng trống chưa hỗ trợ.")};end+=row.size}
        guard end==length else {throw ModError("REL54 dư dữ liệu chưa hỗ trợ.")}
        func translated(_ absolute:Int) throws -> Int {
            let offset=absolute-8
            guard let i=sorted.firstIndex(where:{offset>$0.offset && offset+4<=$0.offset+$0.size}) else {throw ModError("Relocation REL54 vượt record.")}
            return absolute+3*(i+1)
        }
        var data=Data(b[8..<12])
        for row in sorted {data.append(b[8+row.offset]);data.append(contentsOf:[0,0,0]);data.append(b[(9+row.offset)..<(8+row.offset+row.size)])}
        var out=Data();append(54,&out);append(data.count,&out);out.append(data);out.append(b[names..<index]);append(count,&out)
        for row in rows {let i=sorted.firstIndex{$0.offset==row.offset}!;append(row.hash,&out);append(row.offset+3*i,&out);append(row.size+3,&out)}
        var cursor=index+4+count*12
        for _ in 0..<2 {let n=try u(cursor);cursor+=4;guard n<=100000,n<=(b.count-cursor)/4 else {throw ModError("Relocation REL54 bị cắt.")};append(n,&out)
            for _ in 0..<n {append(try translated(u(cursor)),&out);cursor+=4}
        }
        guard cursor==b.count else {throw ModError("Đuôi REL54 chưa hỗ trợ.")};return out
    }
    static func hash(_ name:String)->UInt32 {
        var h:UInt32=0;for c in name.lowercased().utf8 {h=h &+ UInt32(c);h=h &+ (h<<10);h ^= h>>6};h=h &+ (h<<3);h ^= h>>11;return h &+ (h<<15)
    }
    static func profiles(_ b:Data,filename:String) throws -> [String] {
        guard b.count>=24,VehicleInstaller.word(b,0)==151 else {throw ModError("REL151 bị cắt hoặc không hỗ trợ.")}
        let length=Int(VehicleInstaller.word(b,4)),nameAt=8+length
        guard length>=4,nameAt<=b.count-8 else {throw ModError("Data block REL bị hỏng.")}
        let nameLength=Int(VehicleInstaller.word(b,nameAt)),indexAt=nameAt+4+nameLength
        guard nameLength>=4,indexAt<=b.count-4 else {throw ModError("Bảng tên REL bị hỏng.")}
        let count=Int(VehicleInstaller.word(b,indexAt))
        guard count<=100000,count<=(b.count-indexAt-4)/12 else {throw ModError("Index REL bị cắt.")}
        let base=(filename as NSString).lastPathComponent.lowercased()
        let candidate=String(base.dropLast(".dat151.rel".count)).replacingOccurrences(of:"_game",with:"")
        var hashes=Set<UInt32>()
        for i in 0..<count {
            let at=indexAt+4+i*12,h=VehicleInstaller.word(b,at),offset=Int(VehicleInstaller.word(b,at+4)),size=Int(VehicleInstaller.word(b,at+8))
            guard offset>=4,size>0,offset<=length,size<=length-offset else {throw ModError("Mục REL vượt data block.")}
            if b[8+offset]==3 {hashes.insert(h)}
        }
        return ModPack.validName(candidate) && hashes.contains(hash(candidate)) ? [candidate]:[]
    }
}

/// The pinned pgBase page-map encoder only represents pages >=8 KiB. Some valid
/// PC resources include 512/1024/2048/4096-byte tail pages and trap during placement.
/// Merge the tail into a padded ordinary page, preserving every virtual/physical
/// byte and its segment-relative address. Never change textures or geometry.
enum ModResource {
    static func segmentSize(_ flags: UInt32) -> Int {
        let counts = [(27,1,1),(26,1,2),(25,1,4),(24,1,8),(17,127,16),(11,63,32),(7,15,64),(5,3,128),(4,1,256)]
        return counts.reduce(0) { $0 + Int((flags >> $1.0) & UInt32($1.1)) * $1.2 } * (512 << Int(flags & 15))
    }
    static func needsRepair(_ flags: UInt32) -> Bool {
        let base = 512 << Int(flags & 15)
        return [(27,1),(26,2),(25,4),(24,8)].contains { flags & (1 << $0.0) != 0 && base * $0.1 < 8192 }
    }
    static func paddedFlags(_ flags: UInt32) throws -> UInt32 {
        let size = segmentSize(flags)
        for shift in Int(flags & 15)...15 {
            let unit = 8192 << shift
            var units = (size + unit - 1) / unit
            var result = flags & 0xf0000000 | UInt32(shift)
            for (bit,weight,limit) in [(4,16,1),(5,8,3),(7,4,15),(11,2,63),(17,1,127)] {
                let count = min(units / weight, limit);units -= count * weight
                result |= UInt32(count) << bit
            }
            if units == 0 { return result }
        }
        throw ModError("Resource quá lớn để chuyển page map an toàn.")
    }
    /// Only rebuilt when an actual resource requires repair; never decode shaders,
    /// modify metadata semantics, or scan the base game. Used by the manual repair action.
    static func repairedArchive(_ archive: RPFArchive, depth: Int = 0) throws -> Data? {
        guard depth < 8, archive.bytes.count <= 128*1024*1024 else { throw ModError("Gói skin quá lớn hoặc lồng quá sâu.") }
        var files: [String:Data] = [:], changed = false
        for entry in archive.entries {
            if entry.resourceVersion != nil {
                let original = try archive.resourceData(entry)
                let repaired = try normalize(original,name:entry.path)
                files[entry.path] = repaired; changed = changed || original != repaired
            } else if entry.path.hasSuffix(".rpf") {
                let nested = try archive.nested(entry)
                if let repaired = try repairedArchive(nested,depth:depth+1) {files[entry.path]=repaired;changed=true}
                else {files[entry.path]=nested.bytes}
            } else { files[entry.path] = try archive.binary(entry) }
        }
        return changed ? try VehicleInstaller.pack(files) : nil
    }
    static func normalize(_ input: Data, name: String) throws -> Data {
        guard input.count >= 16, input.starts(with: Data("RSC7".utf8)) else { throw ModError("Resource thiếu header: \(name)") }
        func word(_ at: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(input[at+$1]) << (8*$1) } }
        let system = word(8), graphics = word(12)
        let virtualSize = segmentSize(system), physicalSize = segmentSize(graphics)
        guard virtualSize > 0, virtualSize + physicalSize <= 256 * 1024 * 1024 else { throw ModError("Resource vượt ngân sách kiểm tra 256 MiB: \(name)") }
        var raw = Data(count: virtualSize + physicalSize)
        let packed = input.subdata(in:16..<input.count)
        let rawSize = raw.count
        let ok = raw.withUnsafeMutableBytes { o in packed.withUnsafeBytes { i in gi_inflate_resource(i.baseAddress,UInt32(packed.count),o.baseAddress,UInt32(rawSize)) } }
        guard ok == 1 else { throw ModError("Resource nén bị thiếu/hỏng: \(name). Tải lại gói mod đầy đủ.") }
        guard needsRepair(system) || needsRepair(graphics) else { return input }
        let newSystem = needsRepair(system) ? try paddedFlags(system) : system
        let newGraphics = needsRepair(graphics) ? try paddedFlags(graphics) : graphics
        let newVirtual = segmentSize(newSystem), newPhysical = segmentSize(newGraphics)
        var padded = Data(count:newVirtual + newPhysical)
        padded.replaceSubrange(0..<virtualSize,with:raw[0..<virtualSize])
        padded.replaceSubrange(newVirtual..<(newVirtual+physicalSize),with:raw[virtualSize..<raw.count])
        var compressed = Data(count:padded.count + padded.count/1000 + 128)
        let capacity = compressed.count
        let n = compressed.withUnsafeMutableBytes { o in padded.withUnsafeBytes { i in gi_deflate_raw(i.baseAddress,UInt32(padded.count),o.baseAddress,UInt32(capacity)) } }
        guard n > 0 else { throw ModError("Không thể đóng gói resource: \(name)") }
        compressed.count = Int(n)
        var result = Data(input.prefix(16))
        for (at,value) in [(8,newSystem),(12,newGraphics)] { for i in 0..<4 { result[at+i] = UInt8(truncatingIfNeeded:value >> (8*i)) } }
        result.append(compressed)
        return result
    }
}
