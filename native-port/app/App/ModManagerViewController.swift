import UIKit
import UniformTypeIdentifiers

/// Manage validated Legacy vehicle packs, imported from files or folders,
/// and spawn installed add-on/DLC vehicles and iconic GTA V vehicles directly into the game.
final class ModManagerViewController: UITableViewController, UIDocumentPickerDelegate {
    private let engineRunning: Bool
    private let fileManager = FileManager.default
    private var modFiles: [ModFile] = []
    private var dlcCatalog: ModRuntime.Catalog = ModRuntime.Catalog()
    private var scanGeneration = 0
    /// Set by the game screen: spawns through it (with progress and failure messages on the game view).
    var spawnHandler: ((String) -> Void)?

    typealias ModFile = ModFiles.Entry

    private let defaultVehicles: [(name: String, model: String, icon: String)] = [
        ("Karin Sultan (4 cửa)", "sultan", "car.fill"),
        ("Trực thăng Buzzard Attack", "buzzard", "airplane"),
        ("Mô tô bay Oppressor Mk II", "oppressor2", "bolt.car.fill"),
        ("Siêu xe Truffade Adder", "adder", "car.side.fill"),
        ("Mô tô Pegassi Bati 801", "bati", "bicycle")
    ]

    /// The dedicated mods directory: Files › On My iPhone › Mugoat › mods
    static var modsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("mods")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    init(engineRunning: Bool) {
        self.engineRunning = engineRunning
        super.init(style: .insetGrouped)
        title = L10n.text("Quản lý Mod")
        overrideUserInterfaceStyle = .dark
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        tableView.backgroundView = Theme.dimmedBackdrop(image: "SettingsBackground")
        refreshControl = UIRefreshControl()
        refreshControl?.addAction(UIAction { [weak self] _ in self?.scanMods() }, for: .valueChanged)
        _ = Self.modsDirectory
        scanMods()
    }

    private func scanMods() {
        scanGeneration += 1
        let generation = scanGeneration, directory = Self.modsDirectory
        DispatchQueue.global(qos: .utility).async {
            let files = ModFiles.scan(directory), catalog = ModRuntime.catalog(directory)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.scanGeneration == generation else { return }
                self.modFiles = files; self.dlcCatalog = catalog
                self.tableView.reloadData(); self.refreshControl?.endRefreshing()
            }
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 3 // Quản lý & Cài đặt
        case 1: return max(1, modFiles.count) // Tệp mod đã cài
        case 2: return 1 + dlcCatalog.vehicleModels.count + defaultVehicles.count // Gọi xe (Custom + Add-ons + Mặc định)
        default: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return L10n.text("Cài đặt & Tệp Mod")
        case 1: return L10n.text("Danh sách Mod đã cài") + " · \(modFiles.count)"
        case 2: return L10n.text("Gọi phương tiện & Xe Mod (DLC Spawner)")
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Nhập folder, ZIP hoặc DLC RPF xe Legacy. Có thể chọn cùng lúc YFT/YTD và metadata đi kèm. Cài/bật/tắt trước khi vào Story offline; khởi động lại game để áp dụng. Không hỗ trợ ASI hay asset Enhanced."
        case 2:
            return L10n.text("Bấm vào phương tiện để triệu hồi ngay trước mặt nhân vật. Có thể nhập tên model bất kỳ từ bản mod hoặc GTA V gốc.")
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = Theme.rowBackground
        cell.textLabel?.textColor = Theme.text
        cell.detailTextLabel?.textColor = Theme.secondaryText
        cell.detailTextLabel?.numberOfLines = 2

        switch indexPath.section {
        case 0:
            let titles = [
                "Nhập Mod từ tệp / thư mục",
                L10n.text("Vị trí thư mục Mod"),
                L10n.text("Làm mới danh sách Mod")
            ]
            let subs = [
                L10n.text("Chọn tệp từ Tệp hoặc iCloud để tự động cài vào Mugoat"),
                "Files › On My iPhone › Mugoat › mods",
                L10n.text("Quét lại thư mục sau khi chép file qua máy tính hoặc app Tệp")
            ]
            let icons = ["square.and.arrow.down.fill", "folder.fill.badge.gearshape", "arrow.clockwise"]
            cell.textLabel?.text = titles[indexPath.row]
            cell.detailTextLabel?.text = subs[indexPath.row]
            cell.imageView?.image = UIImage(systemName: icons[indexPath.row])
            cell.imageView?.tintColor = Theme.accent
            cell.accessoryType = indexPath.row == 0 ? .disclosureIndicator : .none

        case 1:
            if modFiles.isEmpty {
                cell.textLabel?.text = L10n.text("Chưa có tệp Mod nào")
                cell.detailTextLabel?.text = L10n.text("Bấm 'Nhập Mod từ tệp' ở trên hoặc chép file vào thư mục Mugoat/mods.")
                cell.imageView?.image = UIImage(systemName: "tray")
                cell.imageView?.tintColor = Theme.secondaryText
                cell.selectionStyle = .none
            } else {
                let mod = modFiles[indexPath.row]
                cell.textLabel?.text = mod.name
                let sizeStr = ByteCountFormatter.string(fromByteCount: mod.size, countStyle: .file)
                let dateStr = DateFormatter.localizedString(from: mod.modified, dateStyle: .short, timeStyle: .short)
                cell.detailTextLabel?.text = "\(sizeStr) · \(dateStr) · \(mod.isEnabled ? L10n.text("Đang bật") : L10n.text("Đã tắt"))"
                cell.imageView?.image = UIImage(systemName: mod.isEnabled ? "checkmark.circle.fill" : "xmark.circle")
                cell.imageView?.tintColor = mod.isEnabled ? Theme.accent : .systemGray
                cell.accessoryType = .detailButton
            }

        case 2:
            if indexPath.row == 0 {
                cell.textLabel?.text = L10n.text("Gọi xe theo tên Model (Custom Spawn…)")
                cell.detailTextLabel?.text = L10n.text("Nhập tên model bất kỳ (ví dụ: mbslk, sultan, buzzard…)")
                cell.imageView?.image = UIImage(systemName: "magnifyingglass.circle.fill")
                cell.imageView?.tintColor = Theme.accent
                cell.accessoryType = .disclosureIndicator
            } else if indexPath.row <= dlcCatalog.vehicleModels.count {
                let model = dlcCatalog.vehicleModels[indexPath.row - 1]
                cell.textLabel?.text = "Xe Mod: \(model.uppercased())"
                cell.detailTextLabel?.text = L10n.text("Phương tiện từ gói DLC Add-on đã cài. Bấm để triệu hồi ngay.")
                cell.imageView?.image = UIImage(systemName: "star.fill")
                cell.imageView?.tintColor = .systemYellow
                cell.accessoryType = .disclosureIndicator
            } else {
                let index = indexPath.row - 1 - dlcCatalog.vehicleModels.count
                if index < defaultVehicles.count {
                    let v = defaultVehicles[index]
                    cell.textLabel?.text = v.name
                    cell.detailTextLabel?.text = "Model: \(v.model) · " + L10n.text("Bấm để triệu hồi")
                    cell.imageView?.image = UIImage(systemName: v.icon)
                    cell.imageView?.tintColor = Theme.accent
                    cell.accessoryType = .disclosureIndicator
                }
            }

        default: break
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch indexPath.section {
        case 0:
            if indexPath.row == 0 { pickModFile() }
            else if indexPath.row == 1 { showFolderInfo() }
            else if indexPath.row == 2 { scanMods() }

        case 1:
            guard !modFiles.isEmpty, indexPath.row < modFiles.count else { return }
            toggleMod(at: indexPath.row)

        case 2:
            if indexPath.row == 0 {
                promptCustomVehicleSpawn()
            } else if indexPath.row <= dlcCatalog.vehicleModels.count {
                let model = dlcCatalog.vehicleModels[indexPath.row - 1]
                spawnVehicle(named: model)
            } else {
                let index = indexPath.row - 1 - dlcCatalog.vehicleModels.count
                if index < defaultVehicles.count {
                    spawnVehicle(named: defaultVehicles[index].model)
                }
            }

        default: break
        }
    }

    // MARK: - Mod File Actions

    private func pickModFile() {
        guard !engineRunning else { showAlert("Cần khởi động lại", "Thoát game về launcher trước khi cài hoặc đổi mod."); return }
        let sheet=UIAlertController(title:"Nhập xe Legacy",message:"Chọn ZIP/RPF, thư mục xe hoặc nhiều tệp YFT/YTD/meta cùng lúc.",preferredStyle:.actionSheet)
        for (label,folder) in [("Chọn tệp ZIP/RPF hoặc YFT/YTD/meta",false),("Chọn thư mục xe",true)] {
            sheet.addAction(UIAlertAction(title:label,style:.default){[weak self] _ in
                let picker=UIDocumentPickerViewController(forOpeningContentTypes:folder ? [.folder]:[.data,.archive],asCopy:!folder)
                picker.delegate=self;picker.allowsMultipleSelection=true;self?.present(picker,animated:true)
            })
        }
        sheet.addAction(UIAlertAction(title:"Hủy",style:.cancel));sheet.popoverPresentationController?.sourceView=view
        present(sheet,animated:true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !engineRunning else {return}
        let dest=Self.modsDirectory, game=GameFolder.open()
        view.isUserInteractionEnabled=false
        let progress=UIActivityIndicatorView(style:.large);progress.center=view.center;view.addSubview(progress);progress.startAnimating()
        DispatchQueue.global(qos:.userInitiated).async {
            var reports:[String]=[],errors:[String]=[],base=Set<String>()
            if let game,let data=try? Data(contentsOf:game.appendingPathComponent("common/data/levels/gta5/vehicles.meta")),let xml=try? ModXML.read(data) {base=Set((xml.values["modelName"] ?? []).map{$0.lowercased()})}
            let fm=FileManager.default, group=fm.temporaryDirectory.appendingPathComponent("loose-car-"+UUID().uuidString)
            defer {try? fm.removeItem(at:group)}
            var loose=false
            for u in urls {
                let scoped=u.startAccessingSecurityScopedResource();defer{if scoped{u.stopAccessingSecurityScopedResource()}}
                do {
                    if ["yft","ytd","meta"].contains(u.pathExtension.lowercased()) {
                        try fm.createDirectory(at:group,withIntermediateDirectories:true)
                        try fm.copyItem(at:u,to:group.appendingPathComponent(u.lastPathComponent));loose=true
                    } else {reports += try VehicleInstaller.install(u,into:dest,baseModels:base)}
                } catch {errors.append(u.lastPathComponent+": "+error.localizedDescription)}
            }
            if loose {do {reports += try VehicleInstaller.install(group,into:dest,baseModels:base)} catch {errors.append(error.localizedDescription)}}
            DispatchQueue.main.async {[weak self] in
                guard let self else{return};progress.removeFromSuperview();self.view.isUserInteractionEnabled=true;self.scanMods()
                self.showAlert("Kết quả cài xe",([reports.isEmpty ? "": "Đã cài:\n"+reports.joined(separator:"\n"),errors.isEmpty ? "":"Không cài được:\n"+errors.joined(separator:"\n"),"Khởi động game sau khi cài. Tệp gốc không bị thay đổi."].filter{!$0.isEmpty}).joined(separator:"\n\n"))
            }
        }
    }

    private func toggleMod(at index: Int) {
        guard !engineRunning else {showAlert("Cần khởi động lại", "Chỉ bật/tắt/xóa mod trước khi vào game.");return}
        let mod = modFiles[index]
        let sheet = UIAlertController(title: mod.name, message: L10n.text("Chọn thao tác cho bản mod này:"), preferredStyle: .actionSheet)
        let toggleTitle = mod.isEnabled ? L10n.text("Tắt Mod này (.disabled)") : L10n.text("Bật lại Mod này")
        sheet.addAction(UIAlertAction(title: toggleTitle, style: .default) { [weak self] _ in
            guard let self else { return }
            let newURL: URL
            if mod.isEnabled {
                newURL = mod.url.appendingPathExtension("disabled")
            } else {
                newURL = mod.url.deletingPathExtension()
            }
            try? self.fileManager.moveItem(at: mod.url, to: newURL)
            self.scanMods()
        })
        sheet.addAction(UIAlertAction(title: L10n.text("Xóa vĩnh viễn"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            try? self.fileManager.removeItem(at: mod.url)
            self.scanMods()
        })
        sheet.addAction(UIAlertAction(title: L10n.text("Đóng"), style: .cancel))
        if let cell = tableView.cellForRow(at: IndexPath(row: index, section: 1)) {
            sheet.popoverPresentationController?.sourceView = cell
        }
        present(sheet, animated: true)
    }

    private func showFolderInfo() {
        let path = Self.modsDirectory.path
        let alert = UIAlertController(
            title: L10n.text("Thư mục Mod Mugoat"),
            message: "\(L10n.text("Đường dẫn trên iPhone:"))\n\(path)\n\n\(L10n.text("Mở app 'Tệp' › 'Trên iPhone' › 'Mugoat' › 'mods' để quản lý hoặc chép đè tệp mod."))",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L10n.text("Sao chép đường dẫn"), style: .default) { _ in
            UIPasteboard.general.string = path
        })
        alert.addAction(UIAlertAction(title: L10n.text("Đã hiểu"), style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Vehicle Spawner

    private func spawnVehicle(named model: String) {
        guard engineRunning else {
            showAlert(L10n.text("Chưa vào game"), L10n.text("Vui lòng khởi động và vào game trước khi gọi phương tiện."))
            return
        }
        guard !MugoatOnlineEnabled() else {
            showAlert(L10n.text("Không khả dụng"), L10n.text("Không thể triệu hồi xe trong Online."))
            return
        }
        if let spawnHandler {
            let name = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !name.isEmpty else { return }
            dismiss(animated: true) { spawnHandler(name) }
            return
        }
        var cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleanModel == "mbs1k" { cleanModel = "mbslk" }
        guard !cleanModel.isEmpty else { return }
        let started = cleanModel.withCString { PGSpawnVehicle($0) }
        if started {
            showAlert(L10n.text("Đã gọi xe"), String(format: L10n.text("Đang nạp model '%@'. Xe sẽ xuất hiện ngay trước mặt nhân vật!"), cleanModel))
        } else {
            showAlert(L10n.text("Hệ thống bận"), L10n.text("Đang trong quá trình triệu hồi phương tiện khác. Vui lòng thử lại sau giây lát."))
        }
    }

    private func promptCustomVehicleSpawn() {
        let alert = UIAlertController(
            title: L10n.text("Gọi xe theo tên Model"),
            message: L10n.text("Nhập tên model xe từ bản mod (ví dụ: mbslk) hoặc GTA V gốc (ví dụ: sultan, adder, buzzard):"),
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "mbslk, sultan, buzzard..."
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: L10n.text("Gọi xe ngay"), style: .default) { [weak self, weak alert] _ in
            guard let text = alert?.textFields?.first?.text else { return }
            self?.spawnVehicle(named: text)
        })
        alert.addAction(UIAlertAction(title: L10n.text("Hủy"), style: .cancel))
        present(alert, animated: true)
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.text("Đã hiểu"), style: .default))
        present(alert, animated: true)
    }
}
