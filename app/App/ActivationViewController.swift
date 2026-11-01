import UIKit

/// Dialog presenting the device-bound offline activation prompt for Mugoat Nova.
/// Users copy their 8-character Device ID, send it to the Admin, and enter the generated Key.
final class ActivationViewController: UIViewController, UITextFieldDelegate {
    var onActivated: (() -> Void)?

    private let container = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let deviceBox = UIView()
    private let deviceHeaderLabel = UILabel()
    private let deviceIdLabel = UILabel()
    private let copyButton = UIButton(type: .system)
    private let instructionLabel = UILabel()
    private let keyField = UITextField()
    private let pasteButton = UIButton(type: .system)
    private let errorLabel = UILabel()
    private let activateButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        isModalInPresentation = true
        view.backgroundColor = UIColor.black.withAlphaComponent(0.85)

        setupContainer()
        setupHeader()
        setupDeviceBox()
        setupInstructions()
        setupKeyInput()
        setupButtons()
    }

    private func setupContainer() {
        container.backgroundColor = UIColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 0.96)
        container.layer.cornerRadius = 20
        container.layer.borderWidth = 1.5
        container.layer.borderColor = UIColor.systemYellow.withAlphaComponent(0.65).cgColor
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.6
        container.layer.shadowRadius = 16
        container.layer.shadowOffset = CGSize(width: 0, height: 6)
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            container.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -40),
        ])
    }

    private func setupHeader() {
        titleLabel.text = "MUGOAT NOVA"
        titleLabel.textColor = .systemYellow
        titleLabel.font = .systemFont(ofSize: 22, weight: .black)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        subtitleLabel.text = "KÍCH HOẠT BẢN QUYỀN THIẾT BỊ"
        subtitleLabel.textColor = .white
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            subtitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])
    }

    private func setupDeviceBox() {
        deviceBox.backgroundColor = UIColor.white.withAlphaComponent(0.07)
        deviceBox.layer.cornerRadius = 14
        deviceBox.layer.borderWidth = 1
        deviceBox.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor
        deviceBox.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(deviceBox)

        deviceHeaderLabel.text = "MÃ THIẾT BỊ CỦA BẠN:"
        deviceHeaderLabel.textColor = UIColor(white: 0.8, alpha: 1)
        deviceHeaderLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        deviceHeaderLabel.textAlignment = .center
        deviceHeaderLabel.translatesAutoresizingMaskIntoConstraints = false
        deviceBox.addSubview(deviceHeaderLabel)

        deviceIdLabel.text = LicenseManager.shared.deviceId
        deviceIdLabel.textColor = .white
        deviceIdLabel.font = .monospacedSystemFont(ofSize: 24, weight: .heavy)
        deviceIdLabel.textAlignment = .center
        deviceIdLabel.translatesAutoresizingMaskIntoConstraints = false
        deviceBox.addSubview(deviceIdLabel)

        copyButton.setTitle(" Sao chép mã máy", for: .normal)
        copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        copyButton.tintColor = .systemYellow
        copyButton.setTitleColor(.systemYellow, for: .normal)
        copyButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        copyButton.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        copyButton.layer.cornerRadius = 8
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.addTarget(self, action: #selector(copyDeviceIdTapped), for: .touchUpInside)
        deviceBox.addSubview(copyButton)

        NSLayoutConstraint.activate([
            deviceBox.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 18),
            deviceBox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            deviceBox.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            deviceHeaderLabel.topAnchor.constraint(equalTo: deviceBox.topAnchor, constant: 12),
            deviceHeaderLabel.leadingAnchor.constraint(equalTo: deviceBox.leadingAnchor, constant: 8),
            deviceHeaderLabel.trailingAnchor.constraint(equalTo: deviceBox.trailingAnchor, constant: -8),

            deviceIdLabel.topAnchor.constraint(equalTo: deviceHeaderLabel.bottomAnchor, constant: 6),
            deviceIdLabel.leadingAnchor.constraint(equalTo: deviceBox.leadingAnchor, constant: 8),
            deviceIdLabel.trailingAnchor.constraint(equalTo: deviceBox.trailingAnchor, constant: -8),

            copyButton.topAnchor.constraint(equalTo: deviceIdLabel.bottomAnchor, constant: 10),
            copyButton.centerXAnchor.constraint(equalTo: deviceBox.centerXAnchor),
            copyButton.heightAnchor.constraint(equalToConstant: 34),
            copyButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            copyButton.bottomAnchor.constraint(equalTo: deviceBox.bottomAnchor, constant: -12),
        ])
    }

    private func setupInstructions() {
        instructionLabel.text = "Sao chép mã máy ở trên và gửi cho Admin để nhận Key kích hoạt. Nhập 1 lần dùng vĩnh viễn (Offline 100%, không cần mạng)."
        instructionLabel.textColor = UIColor(white: 0.72, alpha: 1)
        instructionLabel.font = .systemFont(ofSize: 12, weight: .regular)
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(instructionLabel)

        NSLayoutConstraint.activate([
            instructionLabel.topAnchor.constraint(equalTo: deviceBox.bottomAnchor, constant: 14),
            instructionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
        ])
    }

    private func setupKeyInput() {
        let inputRow = UIStackView()
        inputRow.axis = .horizontal
        inputRow.spacing = 8
        inputRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(inputRow)

        keyField.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        keyField.layer.cornerRadius = 10
        keyField.layer.borderWidth = 1
        keyField.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        keyField.textColor = .white
        keyField.font = .monospacedSystemFont(ofSize: 16, weight: .bold)
        keyField.textAlignment = .center
        keyField.autocapitalizationType = .allCharacters
        keyField.autocorrectionType = .no
        keyField.attributedPlaceholder = NSAttributedString(
            string: "NOVA-XXXX-XXXX",
            attributes: [.foregroundColor: UIColor(white: 0.45, alpha: 1)]
        )
        keyField.delegate = self
        keyField.translatesAutoresizingMaskIntoConstraints = false
        inputRow.addArrangedSubview(keyField)

        pasteButton.setTitle("Dán", for: .normal)
        pasteButton.tintColor = .white
        pasteButton.setTitleColor(.white, for: .normal)
        pasteButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        pasteButton.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        pasteButton.layer.cornerRadius = 10
        pasteButton.translatesAutoresizingMaskIntoConstraints = false
        pasteButton.widthAnchor.constraint(equalToConstant: 54).isActive = true
        pasteButton.addTarget(self, action: #selector(pasteKeyTapped), for: .touchUpInside)
        inputRow.addArrangedSubview(pasteButton)

        errorLabel.text = ""
        errorLabel.textColor = UIColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1)
        errorLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            inputRow.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 14),
            inputRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            inputRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            inputRow.heightAnchor.constraint(equalToConstant: 44),

            errorLabel.topAnchor.constraint(equalTo: inputRow.bottomAnchor, constant: 8),
            errorLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            errorLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])
    }

    private func setupButtons() {
        activateButton.setTitle("KÍCH HOẠT & VÀO GAME", for: .normal)
        activateButton.setTitleColor(.black, for: .normal)
        activateButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .black)
        activateButton.backgroundColor = .systemYellow
        activateButton.layer.cornerRadius = 12
        activateButton.translatesAutoresizingMaskIntoConstraints = false
        activateButton.addTarget(self, action: #selector(activateTapped), for: .touchUpInside)
        container.addSubview(activateButton)

        NSLayoutConstraint.activate([
            activateButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 12),
            activateButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            activateButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            activateButton.heightAnchor.constraint(equalToConstant: 48),
            activateButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])
    }

    @objc private func copyDeviceIdTapped() {
        UIPasteboard.general.string = deviceIdLabel.text
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        copyButton.setTitle(" ✓ Đã sao chép!", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.copyButton.setTitle(" Sao chép mã máy", for: .normal)
        }
    }

    @objc private func pasteKeyTapped() {
        if let string = UIPasteboard.general.string {
            keyField.text = string.trimmingCharacters(in: .whitespacesAndNewlines)
            errorLabel.text = ""
        }
    }

    @objc private func activateTapped() {
        keyField.resignFirstResponder()
        guard let input = keyField.text, !input.isEmpty else {
            errorLabel.text = "Vui lòng nhập Key kích hoạt!"
            shakeField()
            return
        }

        let success = LicenseManager.shared.activate(key: input)
        if success {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            errorLabel.textColor = UIColor(red: 0.35, green: 1.0, blue: 0.45, alpha: 1)
            errorLabel.text = "✓ Kích hoạt thành công! Đang vào game..."
            activateButton.isEnabled = false
            activateButton.backgroundColor = UIColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1)
            activateButton.setTitle("✓ ĐÃ KÍCH HOẠT", for: .normal)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.dismiss(animated: true) {
                    self?.onActivated?()
                }
            }
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorLabel.textColor = UIColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1)
            errorLabel.text = "Key không đúng hoặc không khớp với thiết bị này!"
            shakeField()
        }
    }

    private func shakeField() {
        let anim = CAKeyframeAnimation(keyPath: "transform.translation.x")
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.duration = 0.4
        anim.values = [-10, 10, -8, 8, -4, 4, 0]
        keyField.layer.add(anim, forKey: "shake")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        activateTapped()
        return true
    }
}
