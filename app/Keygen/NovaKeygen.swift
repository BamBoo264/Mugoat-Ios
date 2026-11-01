import UIKit
import CryptoKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = KeygenViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class KeygenViewController: UIViewController, UITextFieldDelegate {
    private static let salt = "MugoatNova#2026@SecretLicenseSalt!"

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    // Input Card
    private let inputCard = UIView()
    private let inputLabel = UILabel()
    private let deviceField = UITextField()
    private let pasteButton = UIButton(type: .system)
    private let generateButton = UIButton(type: .system)

    // Result Card
    private let resultCard = UIView()
    private let resultHeaderLabel = UILabel()
    private let resultKeyLabel = UILabel()
    private let copyKeyButton = UIButton(type: .system)

    // History
    private let historyLabel = UILabel()
    private let historyStack = UIStackView()
    private var history: [(device: String, key: String)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1)
        setupScroll()
        setupUI()
    }

    private func setupScroll() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.alignment = .fill
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -30),
        ])
    }

    private func setupUI() {
        // Header
        let headerStack = UIStackView()
        headerStack.axis = .vertical
        headerStack.spacing = 4
        headerStack.alignment = .center

        titleLabel.text = "NOVA KEYGEN"
        titleLabel.textColor = .systemYellow
        titleLabel.font = .systemFont(ofSize: 26, weight: .black)

        subtitleLabel.text = "Bộ tạo Key Mugoat Nova (Admin Offline Tool)"
        subtitleLabel.textColor = UIColor(white: 0.7, alpha: 1)
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .medium)

        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(subtitleLabel)
        contentStack.addArrangedSubview(headerStack)

        // Input Card
        inputCard.backgroundColor = UIColor(red: 0.14, green: 0.15, blue: 0.18, alpha: 1)
        inputCard.layer.cornerRadius = 16
        inputCard.layer.borderWidth = 1
        inputCard.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor

        inputLabel.text = "MÃ THIẾT BỊ CỦA KHÁCH:"
        inputLabel.textColor = .white
        inputLabel.font = .systemFont(ofSize: 12, weight: .bold)

        deviceField.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        deviceField.layer.cornerRadius = 10
        deviceField.textColor = .white
        deviceField.font = .monospacedSystemFont(ofSize: 18, weight: .bold)
        deviceField.textAlignment = .center
        deviceField.autocapitalizationType = .allCharacters
        deviceField.autocorrectionType = .no
        deviceField.attributedPlaceholder = NSAttributedString(
            string: "VD: 0CD2-2316",
            attributes: [.foregroundColor: UIColor(white: 0.4, alpha: 1)]
        )
        deviceField.delegate = self

        pasteButton.setTitle("Dán từ Clipboard", for: .normal)
        pasteButton.setImage(UIImage(systemName: "doc.on.clipboard"), for: .normal)
        pasteButton.tintColor = .systemYellow
        pasteButton.setTitleColor(.systemYellow, for: .normal)
        pasteButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        pasteButton.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        pasteButton.layer.cornerRadius = 8
        pasteButton.addTarget(self, action: #selector(pasteTapped), for: .touchUpInside)

        generateButton.setTitle("TẠO KEY KÍCH HOẠT", for: .normal)
        generateButton.setTitleColor(.black, for: .normal)
        generateButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .black)
        generateButton.backgroundColor = .systemYellow
        generateButton.layer.cornerRadius = 12
        generateButton.addTarget(self, action: #selector(generateTapped), for: .touchUpInside)

        let inputCardStack = UIStackView(arrangedSubviews: [inputLabel, deviceField, pasteButton, generateButton])
        inputCardStack.axis = .vertical
        inputCardStack.spacing = 12
        inputCardStack.translatesAutoresizingMaskIntoConstraints = false
        inputCard.addSubview(inputCardStack)

        NSLayoutConstraint.activate([
            inputCardStack.topAnchor.constraint(equalTo: inputCard.topAnchor, constant: 16),
            inputCardStack.leadingAnchor.constraint(equalTo: inputCard.leadingAnchor, constant: 16),
            inputCardStack.trailingAnchor.constraint(equalTo: inputCard.trailingAnchor, constant: -16),
            inputCardStack.bottomAnchor.constraint(equalTo: inputCard.bottomAnchor, constant: -16),
            deviceField.heightAnchor.constraint(equalToConstant: 44),
            pasteButton.heightAnchor.constraint(equalToConstant: 34),
            generateButton.heightAnchor.constraint(equalToConstant: 46),
        ])
        contentStack.addArrangedSubview(inputCard)

        // Result Card
        resultCard.backgroundColor = UIColor(red: 0.12, green: 0.17, blue: 0.13, alpha: 1)
        resultCard.layer.cornerRadius = 16
        resultCard.layer.borderWidth = 1.5
        resultCard.layer.borderColor = UIColor.systemGreen.withAlphaComponent(0.5).cgColor

        resultHeaderLabel.text = "KEY KÍCH HOẠT CHO KHÁCH:"
        resultHeaderLabel.textColor = UIColor(red: 0.6, green: 0.9, blue: 0.6, alpha: 1)
        resultHeaderLabel.font = .systemFont(ofSize: 12, weight: .bold)

        resultKeyLabel.text = "NOVA-XXXX-XXXX"
        resultKeyLabel.textColor = .white
        resultKeyLabel.font = .monospacedSystemFont(ofSize: 22, weight: .heavy)
        resultKeyLabel.textAlignment = .center

        copyKeyButton.setTitle("Sao chép Key để gửi", for: .normal)
        copyKeyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        copyKeyButton.tintColor = .black
        copyKeyButton.setTitleColor(.black, for: .normal)
        copyKeyButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        copyKeyButton.backgroundColor = UIColor(red: 0.35, green: 0.85, blue: 0.45, alpha: 1)
        copyKeyButton.layer.cornerRadius = 10
        copyKeyButton.addTarget(self, action: #selector(copyKeyTapped), for: .touchUpInside)

        let resultStack = UIStackView(arrangedSubviews: [resultHeaderLabel, resultKeyLabel, copyKeyButton])
        resultStack.axis = .vertical
        resultStack.spacing = 10
        resultStack.translatesAutoresizingMaskIntoConstraints = false
        resultCard.addSubview(resultStack)

        NSLayoutConstraint.activate([
            resultStack.topAnchor.constraint(equalTo: resultCard.topAnchor, constant: 16),
            resultStack.leadingAnchor.constraint(equalTo: resultCard.leadingAnchor, constant: 16),
            resultStack.trailingAnchor.constraint(equalTo: resultCard.trailingAnchor, constant: -16),
            resultStack.bottomAnchor.constraint(equalTo: resultCard.bottomAnchor, constant: -16),
            copyKeyButton.heightAnchor.constraint(equalToConstant: 42),
        ])
        contentStack.addArrangedSubview(resultCard)

        // History
        historyLabel.text = "LỊCH SỬ TẠO GẦN ĐÂY:"
        historyLabel.textColor = UIColor(white: 0.5, alpha: 1)
        historyLabel.font = .systemFont(ofSize: 12, weight: .bold)
        contentStack.addArrangedSubview(historyLabel)

        historyStack.axis = .vertical
        historyStack.spacing = 8
        contentStack.addArrangedSubview(historyStack)
    }

    @objc private func pasteTapped() {
        if let text = UIPasteboard.general.string {
            deviceField.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            generateTapped()
        }
    }

    @objc private func generateTapped() {
        deviceField.resignFirstResponder()
        guard let input = deviceField.text, !input.isEmpty else { return }

        let clean = input.replacingOccurrences(of: "NOVA-", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        let payload = "\(clean):\(Self.salt)"
        let digest = sha256Hex(payload)
        let start = digest.index(digest.startIndex, offsetBy: 8)
        let end = digest.index(start, offsetBy: 8)
        let keySlice = String(digest[start..<end]).uppercased()
        let part1 = String(keySlice.prefix(4))
        let part2 = String(keySlice.suffix(4))
        let finalKey = "NOVA-\(part1)-\(part2)"

        resultKeyLabel.text = finalKey
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Add to history
        let cleanDev = input.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if !history.contains(where: { $0.device == cleanDev }) {
            history.insert((device: cleanDev, key: finalKey), at: 0)
            if history.count > 5 { history.removeLast() }
            refreshHistoryUI()
        }
    }

    @objc private func copyKeyTapped() {
        guard let key = resultKeyLabel.text, key != "NOVA-XXXX-XXXX" else { return }
        UIPasteboard.general.string = key
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        copyKeyButton.setTitle("✓ ĐÃ SAO CHÉP!", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyKeyButton.setTitle("Sao chép Key để gửi", for: .normal)
        }
    }

    private func refreshHistoryUI() {
        historyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in history {
            let row = UIView()
            row.backgroundColor = UIColor(red: 0.14, green: 0.15, blue: 0.18, alpha: 0.7)
            row.layer.cornerRadius = 8

            let devLabel = UILabel()
            devLabel.text = item.device
            devLabel.textColor = UIColor(white: 0.8, alpha: 1)
            devLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)

            let kLabel = UILabel()
            kLabel.text = item.key
            kLabel.textColor = .systemYellow
            kLabel.font = .monospacedSystemFont(ofSize: 13, weight: .bold)

            let hRow = UIStackView(arrangedSubviews: [devLabel, kLabel])
            hRow.axis = .horizontal
            hRow.distribution = .equalSpacing
            hRow.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(hRow)

            NSLayoutConstraint.activate([
                hRow.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
                hRow.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
                hRow.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
                hRow.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8),
            ])
            historyStack.addArrangedSubview(row)
        }
    }

    private func sha256Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        generateTapped()
        return true
    }
}
