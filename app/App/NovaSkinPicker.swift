import UIKit

final class NovaSkinPicker: UITableViewController {
    var selected: ((String) -> Void)?
    private let skins = SkinInstaller.models()

    init() {
        super.init(style: .insetGrouped)
        title = "Đổi skin"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        Theme.styleSettingsTable(tableView)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        skins.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        skins.isEmpty ? "Hãy nhập và bật một skin addon trong Quản lý mod, rồi khởi động lại game." : "Xuống xe trước khi đổi skin."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        var content = cell.defaultContentConfiguration()
        content.text = skins[indexPath.row]
        content.textProperties.color = Theme.text
        cell.backgroundColor = Theme.rowBackground
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let skin = skins[indexPath.row]
        let action = selected
        navigationController?.dismiss(animated: true) { action?(skin) }
    }
}
