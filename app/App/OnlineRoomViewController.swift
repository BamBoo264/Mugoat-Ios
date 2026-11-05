import UIKit

final class OnlineRoomViewController: UIViewController, UITextFieldDelegate {
    private let roomManager = OnlineRoomManager.shared
    var onPlayTapped: (() -> Void)?

    private let scrollView = UIScrollView()
    private let contentView = UIView()

    private let titleLabel = UILabel()
    private let statusCard = UIView()
    private let statusLabel = UILabel()
    private let roomCodeDisplay = UILabel()
    private let copyButton = Theme.glassButton("Sao chép mã phòng", symbol: "doc.on.doc.fill")
    private let hostButton = Theme.primaryButton("Tạo phòng mới", symbol: "plus.circle.fill")

    private let joinCard = UIView()
    private let joinInput = UITextField()
    private let addressInput = UITextField()
    private let pasteButton = Theme.glassButton("Dán mã", symbol: "doc.on.clipboard.fill")
    private let joinButton = Theme.primaryButton("Vào phòng", symbol: "arrow.right.circle.fill")

    private let actionStack = UIStackView()
    private let teleportButton = Theme.glassButton("Dịch chuyển đến bạn chơi", symbol: "location.fill")
    private let leaveButton = Theme.glassButton("Rời phòng", symbol: "xmark.circle.fill")
    private let startGameButton = Theme.primaryButton("Vào Game (Bắt đầu)", symbol: "play.fill")

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupKeyboardHandling()
        bindManager()
        updateUI()
    }

    private func setupUI() {
        view.backgroundColor = UIColor(white: 0.08, alpha: 0.96)
        view.layer.cornerRadius = 24
        view.clipsToBounds = true

        // Dismiss keyboard on background tap
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        // Header
        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.distribution = .equalSpacing

        titleLabel.text = "PHÒNG NOVA INTERNET"
        titleLabel.font = Theme.display(18)
        titleLabel.textColor = Theme.text

        let closeButton = UIButton(type: .close)
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(closeButton)

        // Scroll View Setup
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.keyboardDismissMode = .onDrag
        view.addSubview(header)
        view.addSubview(scrollView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            header.heightAnchor.constraint(equalToConstant: 36),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        // Status & Host Card
        statusCard.backgroundColor = UIColor(white: 0.14, alpha: 0.85)
        statusCard.layer.cornerRadius = 14
        statusCard.layer.borderWidth = 1
        statusCard.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor

        statusLabel.font = Theme.body(13, .medium)
        statusLabel.textColor = Theme.secondaryText
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        roomCodeDisplay.font = .monospacedSystemFont(ofSize: 24, weight: .bold)
        roomCodeDisplay.textColor = .systemGreen
        roomCodeDisplay.textAlignment = .center
        roomCodeDisplay.text = "---- - ----"

        copyButton.addAction(UIAction { [weak self] _ in
            guard let code = self?.roomManager.roomCode else { return }
            UIPasteboard.general.string = code
            let alert = UIAlertController(title: "Đã sao chép", message: "Mã phòng \(code) đã được lưu vào bộ nhớ tạm.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(alert, animated: true)
        }, for: .touchUpInside)

        hostButton.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.dismissKeyboard()
            let code = self.roomManager.createRoom(internet:true)
            self.roomCodeDisplay.text = code
            self.updateUI()
        }, for: .touchUpInside)

        let hostStack = UIStackView(arrangedSubviews: [statusLabel, roomCodeDisplay, copyButton, hostButton])
        hostStack.axis = .vertical
        hostStack.spacing = 8
        hostStack.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(hostStack)
        NSLayoutConstraint.activate([
            hostStack.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 12),
            hostStack.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 14),
            hostStack.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -14),
            hostStack.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -12)
        ])

        // Join Card
        joinCard.backgroundColor = UIColor(white: 0.14, alpha: 0.85)
        joinCard.layer.cornerRadius = 14
        joinCard.layer.borderWidth = 1
        joinCard.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor

        let joinTitle = UILabel()
        joinTitle.text = "HOẶC NHẬP MÃ ĐỂ VÀO PHÒNG"
        joinTitle.font = Theme.body(12, .semibold)
        joinTitle.textColor = Theme.secondaryText
        joinTitle.textAlignment = .center

        joinInput.placeholder = "Nhập mã (VD: K7Q2-M9XD)"
        joinInput.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        joinInput.textColor = .white
        joinInput.backgroundColor = UIColor(white: 0.20, alpha: 0.95)
        joinInput.layer.cornerRadius = 10
        joinInput.textAlignment = .center
        joinInput.autocapitalizationType = .allCharacters
        joinInput.autocorrectionType = .no
        joinInput.returnKeyType = .join
        joinInput.enablesReturnKeyAutomatically = true
        joinInput.delegate = self
        joinInput.heightAnchor.constraint(equalToConstant: 40).isActive = true

        pasteButton.addAction(UIAction { [weak self] _ in
            if let str = UIPasteboard.general.string {
                self?.joinInput.text = OnlineRoomManager.normalizeCode(str)
            }
        }, for: .touchUpInside)

        joinButton.addAction(UIAction { [weak self] _ in
            self?.performJoin()
        }, for: .touchUpInside)

        let inputRow = UIStackView(arrangedSubviews: [joinInput, pasteButton])
        inputRow.axis = .horizontal
        inputRow.spacing = 8
        pasteButton.widthAnchor.constraint(equalToConstant: 100).isActive = true

        addressInput.placeholder="IP máy chủ nếu Bonjour không tìm được (tuỳ chọn)";addressInput.textColor=Theme.text;addressInput.font=Theme.body(13);addressInput.autocapitalizationType = .none;addressInput.autocorrectionType = .no;addressInput.borderStyle = .roundedRect
        let note=UILabel();note.text="Chơi qua Wi-Fi hoặc 4G/5G: một người tạo phòng, người còn lại nhập mã. Cần Nova cùng phiên bản. Đồng bộ nhân vật thử nghiệm; chưa đồng bộ đầy đủ nhiệm vụ, xe hoặc tương thích GTAV-v10.1. Relay Free có hạn mức.";note.font=Theme.body(11);note.textColor=Theme.secondaryText;note.numberOfLines=0
        let joinStack = UIStackView(arrangedSubviews: [joinTitle, inputRow, note, joinButton])
        joinStack.axis = .vertical
        joinStack.spacing = 8
        joinStack.translatesAutoresizingMaskIntoConstraints = false
        joinCard.addSubview(joinStack)
        NSLayoutConstraint.activate([
            joinStack.topAnchor.constraint(equalTo: joinCard.topAnchor, constant: 12),
            joinStack.leadingAnchor.constraint(equalTo: joinCard.leadingAnchor, constant: 14),
            joinStack.trailingAnchor.constraint(equalTo: joinCard.trailingAnchor, constant: -14),
            joinStack.bottomAnchor.constraint(equalTo: joinCard.bottomAnchor, constant: -12)
        ])

        // Action Buttons (Leave / Teleport / Start Game)
        teleportButton.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            if self.roomManager.teleportToPartner() {
                let alert = UIAlertController(title: "Đã dịch chuyển", message: "Đã dịch chuyển tới vị trí của người cùng phòng!", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            } else {
                let alert = UIAlertController(title: "Chưa có toạ độ", message: "Chưa nhận được toạ độ của bạn chơi trong game. Hãy đảm bảo cả hai đã vào trong game!", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }, for: .touchUpInside)

        leaveButton.addAction(UIAction { [weak self] _ in
            self?.dismissKeyboard()
            self?.roomManager.leaveRoom()
            self?.updateUI()
        }, for: .touchUpInside)

        startGameButton.addAction(UIAction { [weak self] _ in
            self?.dismissKeyboard()
            self?.dismiss(animated: true) {
                self?.onPlayTapped?()
            }
        }, for: .touchUpInside)

        actionStack.axis = .vertical
        actionStack.spacing = 8
        actionStack.addArrangedSubview(startGameButton)
        actionStack.addArrangedSubview(teleportButton)
        actionStack.addArrangedSubview(leaveButton)

        // Main Layout inside ScrollView
        let mainStack = UIStackView(arrangedSubviews: [statusCard, joinCard, actionStack])
        mainStack.axis = .vertical
        mainStack.spacing = 10
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    // MARK: - Keyboard Handling

    private func setupKeyboardHandling() {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let flex = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let hideBtn = UIBarButtonItem(title: "Ẩn bàn phím", style: .plain, target: self, action: #selector(dismissKeyboard))
        let joinBarBtn = UIBarButtonItem(title: "Vào phòng", style: .done, target: self, action: #selector(performJoin))
        joinBarBtn.tintColor = .systemGreen
        toolbar.items = [hideBtn, flex, joinBarBtn]
        joinInput.inputAccessoryView = toolbar

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func performJoin() {
        dismissKeyboard()
        guard let text = joinInput.text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        roomManager.joinRoom(code:text,internet:true)
        updateUI()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        performJoin()
        return true
    }

    @objc private func keyboardWillShow(_ note: Notification) {
        guard let userInfo = note.userInfo,
              let frame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboardHeight = frame.height
        scrollView.contentInset.bottom = keyboardHeight + 20
        scrollView.verticalScrollIndicatorInsets.bottom = keyboardHeight + 20

        DispatchQueue.main.async {
            self.scrollView.scrollRectToVisible(self.joinCard.frame, animated: true)
        }
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }

    // MARK: - Manager Binding

    private func bindManager() {
        roomManager.onStateChanged = { [weak self] _ in
            DispatchQueue.main.async { self?.updateUI() }
        }
        roomManager.onPeersUpdated = { [weak self] _ in
            DispatchQueue.main.async { self?.updateUI() }
        }
    }

    private func updateUI() {
        switch roomManager.state {
        case .idle:
            statusLabel.text = "Bạn chưa tham gia phòng nào.\nHãy tạo phòng mới hoặc nhập mã phòng của bạn bè:"
            roomCodeDisplay.text = "---- - ----"
            roomCodeDisplay.textColor = .systemGray
            copyButton.isHidden = true
            hostButton.isHidden = false
            joinCard.isHidden = false
            actionStack.isHidden = true

        case .hosting(let code):
            statusLabel.text = "👑 BẠN LÀ CHỦ PHÒNG\nChia sẻ mã phòng này để bạn bè cùng tham gia:"
            roomCodeDisplay.text = code
            roomCodeDisplay.textColor = .systemGreen
            copyButton.isHidden = false
            hostButton.isHidden = true
            joinCard.isHidden = true
            actionStack.isHidden = false
            teleportButton.isHidden = roomManager.peers.isEmpty
            leaveButton.isHidden = false
            startGameButton.isHidden = false

        case .connecting(let code):
            statusLabel.text = "Đang kết nối tới phòng \(code)..."
            roomCodeDisplay.text = code
            roomCodeDisplay.textColor = .systemOrange
            copyButton.isHidden = true
            hostButton.isHidden = true
            joinCard.isHidden = true
            actionStack.isHidden = false
            teleportButton.isHidden = true
            leaveButton.isHidden = false
            startGameButton.isHidden = true

        case .connected(let code, let isHost):
            let count = roomManager.peers.count + 1
            let roleStr = isHost ? "👑 Chủ phòng (Host)" : "🎮 Khách tham gia (Guest - tự động spawn ở chủ phòng)"
            statusLabel.text = "✅ ĐÃ KẾT NỐI PHÒNG (\(count) người chơi)\n\(roleStr)"
            roomCodeDisplay.text = code
            roomCodeDisplay.textColor = .systemGreen
            copyButton.isHidden = false
            hostButton.isHidden = true
            joinCard.isHidden = true
            actionStack.isHidden = false
            teleportButton.isHidden = false
            leaveButton.isHidden = false
            startGameButton.isHidden = false

        case .error(let msg):
            statusLabel.text = "❌ \(msg)"
            roomCodeDisplay.text = "LỖI"
            roomCodeDisplay.textColor = .systemRed
            copyButton.isHidden = true
            hostButton.isHidden = false
            joinCard.isHidden = false
            actionStack.isHidden = true
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
