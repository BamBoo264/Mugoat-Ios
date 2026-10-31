import UIKit
import UniformTypeIdentifiers

/// Settings › Mods (GTA-69): install a downloaded mod (ModInstaller works out where its files go),
/// and switch installed mods on or off, or remove them. Changes apply the next time the game starts.
final class ModsViewController: UITableViewController, UIDocumentPickerDelegate {
    private var mods: [ModInstaller.Installed] = []
    private var busy = false
    private var importingSound = false
    private var importingSkin = false
    private var femaleSkin = true
    private var skinModelName: String?

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = AppLanguage.choose("Mods")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        reload()
    }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); reload() }
    private func reload() { mods = ModInstaller.installed(); tableView.reloadData() }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 8 : max(mods.count, 1) }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 ? AppLanguage.choose("Installed") : nil
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0
            ? AppLanguage.choose("Pick a mod as you downloaded it (zip, rar, oiv, asi or loose files). The app finds where each file goes. Car, skin and add-on mods need the game files on this iPhone.")
            : AppLanguage.choose("Changes apply the next time the game starts. Mods can cause crashes and glitches that we can't fix: ask about them in the Mods topic on Telegram.")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        cell.accessoryView = nil; cell.accessoryType = .none; cell.selectionStyle = .default
        if indexPath.section == 0 {
            content.text = [busy ? AppLanguage.choose("Reading the mod…") : AppLanguage.choose("Install a mod…"),
                            AppLanguage.choose("Show the Mods folder in Files"), AppLanguage.choose("Mods guide"), "Nhập âm thanh xe…", "Chọn tiếng cho xe…", "Việt hoá cốt truyện…", "Nhập skin addon (Menyoo)…", "Kiểm tra và sửa skin đã cài…"][indexPath.row]
            content.image = UIImage(systemName: ["square.and.arrow.down", "folder", "book", "waveform", "speaker.wave.2", "character.bubble", "person.crop.rectangle", "wrench.and.screwdriver"][indexPath.row])
            content.textProperties.color = tintColor()
        } else if mods.isEmpty {
            content.text = AppLanguage.choose("No mods installed yet")
            content.textProperties.color = .secondaryLabel
            cell.selectionStyle = .none
        } else {
            let mod = mods[indexPath.row]
            content.text = mod.name
            content.secondaryText = AppLanguage.interpolate(AppLanguage.choose("{arg0} files"), [String(mod.files)])
            // Files installed before the game had run: placed at the next start, or (index there) not in this game.
            if mod.waiting > 0 {
                content.secondaryText! += " · " + AppLanguage.interpolate(ModInstaller.hasGameIndex
                    ? AppLanguage.choose("{arg0} not in this game version") : AppLanguage.choose("{arg0} placed when the game starts"), [String(mod.waiting)])
            }
            // Changed while the game is running: applied at the next start (ModInstaller.pending).
            let change = ModInstaller.pending[mod.name]
            if let change {
                content.secondaryText! += " · " + (change == "remove" ? AppLanguage.choose("removed when the game starts again")
                    : change == "on" ? AppLanguage.choose("switched on when the game starts again") : AppLanguage.choose("switched off when the game starts again"))
            }
            let toggle = UISwitch()
            toggle.isOn = change.map { $0 == "on" } ?? mod.enabled
            toggle.isEnabled = change != "remove"
            toggle.addAction(UIAction { [weak self] action in
                guard let self, let toggle = action.sender as? UISwitch else { return }
                do { try ModInstaller.setEnabled(mod, toggle.isOn); if mod.name == BundledMenyoo.name {UserDefaults.standard.set(toggle.isOn,forKey:"NewGenMenyooEnabled")} } catch { toggle.isOn = !toggle.isOn; self.show(error) }
                self.reload()
            }, for: .valueChanged)
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        }
        cell.contentConfiguration = content
        return cell
    }
    private func tintColor() -> UIColor { view.tintColor ?? .systemBlue }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0 else { return }
        if indexPath.row == 7 {
            guard !busy, !ModInstaller.gameRunning else { show(ModError("Sửa skin trước khi vào game. Tắt hẳn app và mở lại nếu đang chơi.")); return }
            busy = true; tableView.reloadData()
            DispatchQueue.global(qos:.userInitiated).async {
                let result = Result { try SkinInstaller.repairInstalled() }
                DispatchQueue.main.async {
                    self.busy = false; self.reload()
                    switch result {
                    case .success(let count):
                        let alert = UIAlertController(title:"Kiểm tra skin hoàn tất",message:"Đã sửa \(count) gói resource. Bản gốc được giữ trong file ẩn .dlc.rpf.before-r004 cạnh DLC. Không thể sửa archive thiếu dữ liệu; các trường hợp đó cần tải lại.",preferredStyle:.alert)
                        alert.addAction(UIAlertAction(title:"OK",style:.default));self.present(alert,animated:true)
                    case .failure(let error):self.show(error)
                    }
                }
            };return
        }
        if indexPath.row == 6 {
            guard !busy, !ModInstaller.gameRunning else { show(ModError("Nhập skin trước khi vào game; tắt hẳn và mở lại app nếu đang chơi.")); return }
            importingSound = false; importingSkin = true
            let menu = UIAlertController(title: "Loại skin addon", message: "Chọn ZIP/RAR/thư mục hoặc nhiều file cùng lúc. Mỗi model cần đủ YDD, YFT, YMT, YTD. Gói 2B/A2 chọn Nữ.", preferredStyle: .alert)
            menu.addTextField { field in
                field.placeholder = "Tên model ngắn (để trống giữ tên gốc)"
                field.autocapitalizationType = .none; field.autocorrectionType = .no
            }
            for female in [true, false] {
                menu.addAction(UIAlertAction(title: female ? "Nữ (2B/A2)" : "Nam", style: .default) { _ in
                    self.femaleSkin = female
                    self.skinModelName = SkinInstaller.normalizedName(menu.textFields?.first?.text ?? "")
                    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .folder], asCopy: true)
                    picker.delegate = self; picker.allowsMultipleSelection = true
                    self.present(picker, animated: true)
                })
            }
            menu.addAction(UIAlertAction(title: "Hủy", style: .cancel))
            present(menu, animated: true); return
        }
        if indexPath.row == 5 { chooseTranslation();return }
        if indexPath.row == 4 { chooseSound();return }
        if indexPath.row == 0 || indexPath.row == 3 {
            importingSkin = false
            importingSound = indexPath.row == 3
            guard !busy else { return }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .folder], asCopy: true)
            picker.delegate = self
            picker.allowsMultipleSelection = true
            present(picker, animated: true)
        } else if indexPath.row == 2 {
            if let url = URL(string: "https://github.com/Living-NG/GTA-NEW-GEN-2/blob/main/docs/MODS.md") { UIApplication.shared.open(url) }
        } else {
            try? FileManager.default.createDirectory(at: ModInstaller.modsFolder, withIntermediateDirectories: true)
            if let url = URL(string: "shareddocuments://" + ModInstaller.modsFolder.path) { UIApplication.shared.open(url) }
        }
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1, !mods.isEmpty else { return nil }
        let mod = mods[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: AppLanguage.choose("Remove")) { [weak self] _, _, done in
            do { try ModInstaller.remove(mod) } catch { self?.show(error, title: AppLanguage.choose("Couldn't remove the mod")) }
            self?.reload(); done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    // MARK: Installing

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty else { return }
        if importingSound {installSound(urls)}else{install(urls)}
    }

    /// Unpacks and plans in the background, then asks before copying.
    func install(_ url: URL) { install([url]) }
    private func install(_ urls: [URL]) {
        busy = true; tableView.reloadData()
        let manifest = EnginePaths.manifest
        let game = GameFolder.open()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () -> (ModInstaller.Plan, URL) in
                let folder = try ModInstaller.unpackMany(urls)
                var index=ModInstaller.GameIndex.load(manifest:manifest)
                if let game{ModInstaller.addStockVehicleIndex(game,to:&index)}
                let name=urls.count==1 ? urls[0].lastPathComponent:"Xe_"+urls[0].deletingPathExtension().lastPathComponent
                let plan: ModInstaller.Plan
                do {
                    if self.importingSkin { plan = try SkinInstaller.plan(folder:folder,name:name,female:self.femaleSkin,modelName:self.skinModelName) }
                    else if SoundInstaller.isSoundOnly(folder) {
                        guard !ModInstaller.gameRunning else { throw ModError("Nhập audio trước khi vào game; hãy tắt hẳn và mở lại app.") }
                        plan = try SoundInstaller.build(folder).0
                    } else { plan = ModInstaller.plan(folder:folder,name:name,index:index) }
                }
                catch { try? FileManager.default.removeItem(at:folder); throw error }
                return (plan, folder)
            }
            DispatchQueue.main.async {
                self.busy = false; self.tableView.reloadData()
                switch result {
                case let .failure(error): self.show(error)
                case let .success((plan, folder)): self.confirm(plan, folder: folder)
                }
            }
        }
    }

    private func confirm(_ plan: ModInstaller.Plan, folder: URL) {
        var lines: [String] = []
        for item in plan.items.prefix(12) { lines.append("• " + (item.target as NSString).lastPathComponent + " → " + item.note) }
        if plan.items.count > 12 { lines.append(AppLanguage.interpolate(AppLanguage.choose("…and {arg0} more"), [String(plan.items.count - 12)])) }
        if !plan.skipped.isEmpty {
            lines.append("")
            lines.append(AppLanguage.choose("Not installed:"))
            for skip in plan.skipped.prefix(8) { lines.append("• " + (skip.file as NSString).lastPathComponent + ": " + skip.reason) }
        }
        guard !plan.items.isEmpty else {
            // Left out because it can't work on iPhone (Windows .NET, GTA V Enhanced): say so, not "couldn't tell where".
            let title = plan.unsupported ? AppLanguage.choose("This mod can't run on iPhone") : AppLanguage.choose("Nothing to install")
            let help = plan.unsupported ? AppLanguage.choose("It needs something that only runs on a Windows PC, or it was made for another version of the game. The guide lists what works.")
                : AppLanguage.choose("The app couldn't tell where this mod's files go. See the guide for putting files in the Mods folder by hand.")
            let alert = UIAlertController(title: title, message: lines.joined(separator: "\n") + "\n\n" + help, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: AppLanguage.choose("OK"), style: .cancel) { _ in try? FileManager.default.removeItem(at: folder) })
            present(alert, animated: true); return
        }
        let alert = UIAlertController(title: AppLanguage.interpolate(AppLanguage.choose("Install \"{arg0}\"?"), [plan.name]), message: lines.joined(separator: "\n"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: AppLanguage.choose("Cancel"), style: .cancel) { _ in try? FileManager.default.removeItem(at: folder) })
        alert.addAction(UIAlertAction(title: AppLanguage.choose("Install"), style: .default) { [weak self] _ in
            do {
                try ModInstaller.install(plan)
                NSLog("Mods: installed %@ (%d files, %d skipped)", plan.name, plan.items.count, plan.skipped.count)
            } catch { self?.show(error) }
            try? FileManager.default.removeItem(at: folder)
            self?.reload()
        })
        present(alert, animated: true)
    }

    private func installSound(_ urls:[URL]) {
        guard !ModInstaller.gameRunning else{show(ModError("Hãy tắt hẳn và mở lại app, nhập audio trước khi chơi để không thay bank game đang dùng."));return}
        busy=true;tableView.reloadData()
        DispatchQueue.global(qos:.userInitiated).async {
            let result=Result {() -> (ModInstaller.Plan,URL) in
                let stage=try SoundInstaller.stage(urls)
                do {let (plan,_)=try SoundInstaller.build(stage);return(plan,stage)}
                catch{try? FileManager.default.removeItem(at:stage);throw error}
            }
            DispatchQueue.main.async {
                self.busy=false;self.tableView.reloadData()
                switch result {
                case let .success((plan,stage)):self.confirm(plan,folder:stage)
                case let .failure(error):self.show(error)
                }
            }
        }
    }
    private func chooseSound(){
        let profiles=SoundInstaller.available()
        guard !profiles.isEmpty else{show(ModError("Nhập gói âm thanh trước, rồi tắt hẳn và mở lại app để game nạp bank."));return}
        let cars=ModVehicleSupport.vehicles()
        guard !cars.isEmpty else{show(ModError("Chưa có xe mod trong danh sách. Khởi động game một lần sau khi nhập xe."));return}
        let ask=UIAlertController(title:"Chọn xe đã mod",message:"Chọn xe rồi chọn tiếng động cơ. Sau khi nhập gói sound cần mở lại app.",preferredStyle:.alert)
        for name in cars {
            ask.addAction(UIAlertAction(title:name,style:.default){[weak self] _ in
                let model=ModAudio.hash(name)
                let menu=UIAlertController(title:"Âm thanh: \(name)",message:nil,preferredStyle:.alert)
                for profile in profiles {menu.addAction(UIAlertAction(title:profile,style:.default){_ in SoundAssignments.set(model,profile)})}
                menu.addAction(UIAlertAction(title:"Bỏ gán (xe mới dùng tiếng gốc)",style:.default){_ in SoundAssignments.set(model,"")})
                menu.addAction(UIAlertAction(title:"Huỷ",style:.cancel));self?.present(menu,animated:true)
            })
        }
        ask.addAction(UIAlertAction(title:"Huỷ",style:.cancel));present(ask,animated:true)
    }
    private func chooseTranslation(){
        let menu=UIAlertController(title:"Việt hoá tích hợp",message:"Áp dụng khi mở lại app. Có dấu dùng font kèm gói Việt hoá; nếu chữ lỗi hãy chọn không dấu.",preferredStyle:.alert)
        for (mode,title) in [(1,"Tiếng Việt có dấu"),(2,"Tiếng Việt không dấu"),(0,"Tắt Việt hoá")] {
            menu.addAction(UIAlertAction(title:title,style:.default){_ in UserDefaults.standard.set(mode,forKey:"NewGenVietnameseMode")})
        }
        menu.addAction(UIAlertAction(title:"Huỷ",style:.cancel));present(menu,animated:true)
    }

    private func show(_ error: Error, title: String = AppLanguage.choose("Couldn't install the mod")) {
        let alert = UIAlertController(title: title, message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: AppLanguage.choose("OK"), style: .cancel))
        present(alert, animated: true)
    }
}
