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
                                    resourceVersion: resource ? Int(((UInt32(unpacked) >> 28) << 4) | (flags >> 28)) : nil))
            }
        }
        try walk(0, parent: "", depth: 0)
        guard visited.count == count, Set(output.map(\.path)).count == output.count else { throw ModError("Bảng RPF chứa mục mồ côi hoặc trùng tên.") }
        entries = output
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

final class ModXML: NSObject, XMLParserDelegate {
    private var current = "", text = ""
    private var stack: [String] = [], row: [String:String] = [:]
    private(set) var audioPolicies: [(model:String,profile:String,kind:String)] = []
    private(set) var values: [String: [String]] = [:]
    static func read(_ data: Data) throws -> ModXML {
        let delegate = ModXML(), parser = XMLParser(data: try VehicleInstaller.cleanXML(data))
        parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse() else { throw ModError("XML của mod không hợp lệ.") }
        return delegate
    }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) { current = name; text = ""; stack.append(name)
        if stack.count == 3 && stack[1] == "InitDatas" && name == "Item" { row = [:] }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == current { let value = text.trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty { values[name, default: []].append(value) } }
        if stack.count == 4 && stack[1] == "InitDatas" && stack[2] == "Item" { row[name] = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if stack.count == 3 && stack[1] == "InitDatas" && name == "Item", let model = row["modelName"], !model.isEmpty {
            let profile = row["audioNameHash"] ?? ""
            audioPolicies.append((model,profile.isEmpty ? model : profile,row["vehicleClass"] ?? ""))
        }
        stack.removeLast(); current = ""; text = ""
    }
}

struct ModPack {
    let name: String
    let url: URL
    let models: [String]
    let vehicleModels: [String]
    let audioPolicies: [(model:String,profile:String,kind:String)]
    let archive: RPFArchive
    static func validName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count<=63 && name.utf8.allSatisfy{(97...122).contains($0)||(48...57).contains($0)||$0==95}
    }
    init(url: URL) throws {
        let archive=try RPFArchive(url:url)
        guard let setup=archive.entries.first(where:{$0.path=="setup2.xml"}),archive.entries.contains(where:{$0.path=="content.xml"}) else {throw ModError("DLC thiếu setup2.xml hoặc content.xml.")}
        let xml=try ModXML.read(archive.metadata(setup))
        guard let device=xml.values["deviceName"]?.first?.lowercased(),device.hasPrefix("dlc_"),Self.validName(String(device.dropFirst(4))) else {throw ModError("DLC không có deviceName hợp lệ.")}
        name=String(device.dropFirst(4));self.url=url;self.archive=archive
        var audio: [(model:String,profile:String,kind:String)] = []
        var vehicles=Set<String>(),peds=Set<String>(),fragments=Set<String>(),total=0
        func scan(_ rpf:RPFArchive,_ depth:Int) throws {
            guard depth<=4 else {throw ModError("DLC lồng archive quá sâu.")}
            for e in rpf.entries {
                if e.path.hasSuffix("vehicles.meta") {
                    let parsed = try ModXML.read(rpf.metadata(e)); audio += parsed.audioPolicies
                    for m in parsed.values["modelName"] ?? [] {let n=m.lowercased();guard Self.validName(n) else {throw ModError("Model không hợp lệ: \(n)")};vehicles.insert(n)}
                } else if e.path.hasSuffix("peds.meta") {
                    let data=try ModXML.read(rpf.metadata(e));for m in (data.values["ModelName"] ?? [])+(data.values["Name"] ?? []) {if Self.validName(m.lowercased()){peds.insert(m.lowercased())}}
                } else if e.path.hasSuffix(".rpf") {
                    total+=e.size;guard total<=512*1024*1024 else {throw ModError("Archive lồng vượt giới hạn 512 MiB.")};try scan(rpf.nested(e),depth+1)
                } else if e.path.hasSuffix(".yft") || e.path.hasSuffix(".ytd") || e.path.hasSuffix(".ydd") {
                    let expected=e.path.hasSuffix(".yft") ? 162:e.path.hasSuffix(".ytd") ? 13:165
                    guard e.resourceVersion==expected else {throw ModError("\(e.path): tài nguyên Enhanced hoặc version không hỗ trợ; cần bản Legacy.")}
                    if e.path.hasSuffix(".yft") {let n=String((e.path as NSString).lastPathComponent.dropLast(4));if !n.hasSuffix("_hi"){fragments.insert(n)}}
                }
            }
        }
        try scan(archive,0)
        if vehicles.isEmpty {vehicles=fragments} // replacement pack: engine already owns model metadata
        guard !vehicles.isEmpty || !peds.isEmpty else {throw ModError("DLC không chứa model có thể nạp.")}
        guard vehicles.isSubset(of:fragments) else {throw ModError("DLC khai báo xe nhưng thiếu YFT: \(vehicles.subtracting(fragments).sorted().joined(separator:", "))")}
        audioPolicies=audio.filter { vehicles.contains($0.model) }; vehicleModels=vehicles.sorted();models=vehicles.union(peds).sorted()
    }
}
