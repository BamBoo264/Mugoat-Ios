import Foundation

/// Register non-streamed addon peds as startup DLCs; segment-relative model bytes are retained; small resource pages are padded at import.
/// A complete quartet distinguishes a ped from a loose replacement vehicle.
enum SkinInstaller {
    static func normalizedName(_ value: String) -> String {
        value.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"vi_VN")).lowercased().replacingOccurrences(of:"đ",with:"d").filter { !$0.isWhitespace }
    }
    static let extensions: Set<String> = ["ydd", "yft", "ymt", "ytd"]
    static func plan(folder: URL, name: String, female: Bool = true, modelName: String? = nil) throws -> ModInstaller.Plan {
        let fm = FileManager.default
        var groups: [String: [String: URL]] = [:]
        guard let walk = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { throw ModError("Không đọc được thư mục skin.") }
        for case let url as URL in walk {
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard info.isSymbolicLink != true else { throw ModError("Không nhập symlink.") }
            let ext = url.pathExtension.lowercased()
            guard info.isRegularFile == true, extensions.contains(ext) else { continue }
            let model = url.deletingPathExtension().lastPathComponent.lowercased()
            guard ModPack.validName(model) || modelName.map(normalizedName).map({ !$0.isEmpty }) == true else { throw ModError("Tên model skin chỉ được có chữ, số và dấu gạch dưới: \(model)") }
            if let prior = groups[model]?[ext], prior != url { throw ModError("Có nhiều biến thể cùng tên \(model). Hãy chọn riêng một thư mục biến thể.") }
            groups[model, default: [:]][ext] = url
        }
        guard !groups.isEmpty, groups.count <= 32 else { throw ModError("Chọn từ 1 tới 32 skin, mỗi skin đủ YDD, YFT, YMT, YTD. Skin streamed có thư mục thành phần cần gói DLC riêng.") }
        let alias = modelName.map(normalizedName).flatMap { $0.isEmpty ? nil : $0 }
        if let alias {
            guard groups.count == 1, alias.utf8.count <= 63, ModPack.validName(alias) else { throw ModError("Đổi tên khi nhập một skin; dùng tối đa 63 chữ thường a-z, số hoặc _. Nhập nhiều skin: để trống tên.") }
        }
        let installingName = ModInstaller.cleanName(name)
        let occupied = ModInstaller.installed().filter { $0.name != installingName }.flatMap { mod -> [String] in
            guard let d = try? Data(contentsOf:mod.url.appendingPathComponent("skin-models.json")), let names = try? JSONSerialization.jsonObject(with:d) as? [String] else { return [] }
            return names
        }
        let incoming = alias.map { [$0] } ?? groups.keys.sorted()
        guard Set(occupied).isDisjoint(with:incoming) else { throw ModError("Tên model skin đã được dùng. Chọn tên khác hoặc gỡ skin cũ trước.") }
        var plan = ModInstaller.Plan(name: installingName)
        plan.kinds.insert("skin-addon")
        let output = folder.appendingPathComponent(".newgen-skin-output")
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        for original in groups.keys.sorted() {
            let group = groups[original]!
            let model = alias ?? original
            guard Set(group.keys) == extensions else { throw ModError("Skin \(model) thiếu: \(extensions.subtracting(group.keys).sorted().joined(separator: ", ")). Chọn cả bốn tệp hoặc ZIP/thư mục đầy đủ.") }
            var assets: [String: Data] = [:]
            for ext in extensions {
                let url = group[ext]!
                if let size = (try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue, size > 64 * 1024 * 1024 { throw ModError("Tệp skin vượt 64 MiB: \(url.lastPathComponent)") }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                guard data.count >= 16, data.starts(with: Data("RSC7".utf8)) else { throw ModError("Tệp skin không phải RSC7 Legacy: \(url.lastPathComponent)") }
                var why = [CChar](repeating: 0, count: 200)
                guard !PGModFileProblem(url.path, &why, why.count) else { throw ModError("Skin không tương thích: \(String(cString: why))") }
                assets[model + "." + ext] = try ModResource.normalize(data, name: url.lastPathComponent)
            }
            // One pack per model avoids accumulating every skin's textures in memory.
            let packName = "ngped_" + String(ModAudio.hash(model), radix: 16)
            let device = "dlc_" + packName, change = packName + "_STARTUP"
            let mounts = [("peds.rpf", "RPF_FILE"), ("peds.meta", "PED_METADATA_FILE")]
            let entries = mounts.map { "<Item><filename>\(device):/\($0.0)</filename><fileType>\($0.1)</fileType><locked value=\"false\"/><disabled value=\"true\"/><persistent value=\"true\"/><overlay value=\"false\"/></Item>" }.joined()
            let enable = mounts.map { "<Item>\(device):/\($0.0)</Item>" }.joined()
            let setup = "<SSetupData><deviceName>\(device)</deviceName><datFile>content.xml</datFile><nameHash>\(packName)</nameHash><contentChangeSetGroups><Item><NameHash>GROUP_STARTUP</NameHash><ContentChangeSets><Item>\(change)</Item></ContentChangeSets></Item></contentChangeSetGroups><type>EXTRACONTENT_COMPAT_PACK</type><order value=\"1002\"/></SSetupData>"
            let content = "<CDataFileMgr__ContentsOfDataFileXml><disabledFiles/><includedXmlFiles/><includedDataFiles/><dataFiles>\(entries)</dataFiles><contentChangeSets><Item><changeSetName>\(change)</changeSetName><filesToEnable>\(enable)</filesToEnable></Item></contentChangeSets><patchFiles/></CDataFileMgr__ContentsOfDataFileXml>"
            let pack = try VehicleInstaller.pack(["peds.rpf": try VehicleInstaller.pack(assets), "peds.meta": metadata(model: model, female: female), "setup2.xml": Data(setup.utf8), "content.xml": Data(content.utf8)])
            let file = output.appendingPathComponent(packName + ".rpf")
            try pack.write(to: file, options: .atomic)
            plan.items.append(.init(source: file, target: "update/x64/dlcpacks/\(packName)/dlc.rpf", note: "Skin addon: \(model)"))
        }
        let list = output.appendingPathComponent("skin-models.json")
        try JSONSerialization.data(withJSONObject: alias.map { [$0] } ?? groups.keys.sorted()).write(to: list)
        plan.items.append(.init(source: list, target: "skin-models.json", note: "Danh sách model cho Menyoo"))
        return plan
    }
    static func metadata(model: String, female: Bool) -> Data {
        let sex = female ? "FEMALE" : "MALE", lower = female ? "f" : "m"
        let values = [
            ("Name", model), ("PropsName", "null"), ("ClipDictionaryName", "move_\(lower)@generic"),
            ("BlendShapeFileName", "null"), ("ExpressionSetName", "expr_set_ambient_\(sex.lowercased())"),
            ("ExpressionDictionaryName", "null"), ("ExpressionName", "null"), ("Pedtype", "CIV\(sex)"),
            ("MovementClipSet", "move_\(lower)@multiplayer"), ("StrafeClipSet", "move_ped_strafing"),
            ("MovementToStrafeClipSet", "move_ped_to_strafe"), ("InjuredStrafeClipSet", "move_strafe_injured"),
            ("FullBodyDamageClipSet", "dam_ko"), ("AdditiveDamageClipSet", "dam_ad"),
            ("DefaultGestureClipSet", "ANIM_GROUP_GESTURE_\(lower.uppercased())_GENERIC"),
            ("FacialClipsetGroupName", "facial_clipset_group_gen_\(sex.lowercased())"),
            ("DefaultVisemeClipSet", "ANIM_GROUP_VISEMES_\(lower.uppercased())_LO"),
            ("SidestepClipSet", "CLIP_SET_ID_INVALID"), ("PoseMatcherName", "Male"), ("PoseMatcherProneName", "Male_prone"),
            ("GetupSetHash", "NMBS_SLOW_GETUPS"), ("CreatureMetadataName", "null"), ("DecisionMakerName", "DEFAULT"),
            ("MotionTaskDataSetName", "STANDARD_PED"), ("DefaultTaskDataSetName", "STANDARD_PED"),
            ("PedCapsuleName", female ? "STANDARD_FEMALE" : "STANDARD_MALE"), ("RelationshipGroup", "CIV\(sex)"),
            ("NavCapabilitiesName", "STANDARD_PED"), ("PerceptionInfo", "DEFAULT_PERCEPTION"), ("DefaultBrawlingStyle", "BS_AI"),
            ("DefaultUnarmedWeapon", "WEAPON_UNARMED"), ("Personality", "\(female ? "Female" : "Male")"),
            ("CombatInfo", "DEFAULT"), ("VfxInfoName", "VFXPEDINFO_HUMAN_GENERIC"), ("AmbientClipsForFlee", "FLEE"),
            ("PedVoiceGroup", "SILENT_PVG"), ("AbilityType", "SAT_NONE"), ("ThermalBehaviour", "TB_WARM"),
            ("SuperlodType", "SLOD_HUMAN"), ("ScenarioPopStreamingSlot", "SCENARIO_POP_STREAMING_NORMAL"), ("DefaultSpawningPreference", "DSP_NORMAL")
        ]
        let fields = values.map { "<\($0.0)>\($0.1)</\($0.0)>" }.joined()
        return Data(("<?xml version=\"1.0\"?><CPedModelInfo__InitDataList><residentTxd>comp_peds_generic</residentTxd><residentAnims/><InitDatas><Item>" + fields + "<IsStreamedGfx value=\"false\"/><IsHeadBlendPed value=\"false\"/><CanSpawnInCar value=\"true\"/><HDDist value=\"3.0\"/><TargetingThreatModifier value=\"1.0\"/><DefaultRemoveRangeMultiplier value=\"1.0\"/></Item></InitDatas><multiTxdRelationships/></CPedModelInfo__InitDataList>").utf8)
    }
    /// Explicit pre-game repair, not recurring startup work. Originals kept beside
    /// the archive as hidden backups, so native mod enumeration cannot mount them.
    static func repairInstalled() throws -> Int {
        guard !ModInstaller.gameRunning else { throw ModError("Tắt hẳn game và mở lại app trước khi sửa skin.") }
        let fm = FileManager.default
        var repairedCount = 0
        for mod in ModInstaller.installed() where fm.fileExists(atPath:mod.url.appendingPathComponent("skin-models.json").path) {
            let files = (fm.enumerator(at:mod.url,includingPropertiesForKeys:[.isRegularFileKey],options:.skipsHiddenFiles)?.allObjects as? [URL] ?? []).filter { $0.lastPathComponent.lowercased() == "dlc.rpf" }
            for file in files {
                let archive = try RPFArchive(url:file)
                guard let data = try ModResource.repairedArchive(archive) else { continue }
                let backup = file.deletingLastPathComponent().appendingPathComponent(".dlc.rpf.before-r004")
                if !fm.fileExists(atPath:backup.path) { try fm.copyItem(at:file,to:backup) }
                // .atomic keeps the old DLC intact if writing fails.
                try data.write(to:file,options:.atomic)
                repairedCount += 1
            }
        }
        return repairedCount
    }
    static func models() -> [String] {
        Array(Set(ModInstaller.installed().filter(\.enabled).flatMap { mod -> [String] in
            guard let data = try? Data(contentsOf: mod.url.appendingPathComponent("skin-models.json")), let names = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
            return names.filter { ModPack.validName($0) }
        })).sorted()
    }
    static func updateMenyooList() throws {
        let packages = ModInstaller.installed().filter { $0.name == BundledMenyoo.name }
        guard packages.count == 1, let mod = packages.first else { return }
        guard FileManager.default.fileExists(atPath: mod.url.appendingPathComponent(".newgen-menyoo").path) else { return }
        let file = mod.url.appendingPathComponent("menyooStuff/PedList.xml")
        var text = try String(contentsOf: file, encoding: .utf8)
        let begin = "<!-- NewGen addon peds -->", end = "<!-- /NewGen addon peds -->"
        if let a = text.range(of: begin), let b = text.range(of: end, range: a.upperBound..<text.endIndex) { text.removeSubrange(a.lowerBound..<b.upperBound) }
        guard let closing = text.range(of: "</PedList>") else { throw ModError("PedList.xml của Menyoo không hợp lệ.") }
        let peds = models().map { "<Ped name=\"\($0)\" caption=\"\($0)\"/>" }.joined()
        text.insert(contentsOf: begin + "<Category name=\"Skin addon NewGen\">" + peds + "</Category>" + end, at: closing.lowerBound)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
}
