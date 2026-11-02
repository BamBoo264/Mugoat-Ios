import UIKit

final class OnlineRoomViewController: UIViewController {
    private let roomManager = OnlineRoomManager.shared
    var onPlayTapped: (() -> Void)?

    private let titleLabel = UILabel()
    private let statusCard = UIView()
    private let statusLabel = UILabel()
    private let roomCodeDisplay = UILabel()
    private let copyButton = Theme.glassButton("Sao chép mã phòng", symbol: "doc.on.doc.fill")
    private let hostButton = Theme.primaryButton("Tạo phòng mới", symbol: "plus.circle.fill")
    
    private let joinInput = UITextField()
    private let joinButton = Theme.primaryButton("Vào phòng", symbol: "arrow.right.circle.fill")
    private let leaveButton = Theme.glassButton("Rời phòng", symbol: "xmark.circle.fill")
    private let startGameButton = Theme.primaryButton("Vào Game (Bắt đầu)", symbol: "play.fill")
    
    private let playersTableView = UITableView()
    private var playerList: [OnlinePeer] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindManager()
        updateUI()
    }

    private func setupUI() {
        view.backgroundColor = UIColor(white: 0.08, alpha: 0.95)
        view.layer.cornerRadius = 24
        view.clipsToBounds = true

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.distribution = .equalSpacing

        titleLabel.text = "GTA ONLINE · PHÒNG CHƠI"
        titleLabel.font = Theme.display(20)
        titleLabel.textColor = Theme.text

        let closeButton = UIButton(type: .close)
        closeButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(closeButton)

        // Status Card
        statusCard.backgroundColor = UIColor(white: 0.15, alpha: 0.8)
        statusCard.layer.cornerRadius = 16
        statusCard.layer.borderWidth = 1
        statusCard.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor

        statusLabel.font = Theme.body(14, .medium)
        statusLabel.textColor = Theme.secondaryText
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        roomCodeDisplay.font = .monospacedSystemFont(ofSize: 28, weight: .bold)
        roomCodeDisplay.textColor = .systemGreen
        roomCodeDisplay.textAlignment = .center
        roomCodeDisplay.text = "---- - ----"

        copyButton.addAction(UIAction { [weak self] _ in
            guard let code = self?.roomManager.roomCode else { return }
            UIPasteboard.general.string = code
            let alert = UIAlertController(title: "Đã chép", message: "Mã phòng \(code) đã được lưu vào bộ nhớ tạm.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(alert, animated: true)
        }, for: .touchUpInside)

        hostButton.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            let code = self.roomManager.createRoom()
            self.roomCodeDisplay.text = code
            self.updateUI()
        }, for: .touchUpInside)

        let statusStack = UIStackView(arrangedSubviews: [statusLabel, roomCodeDisplay, copyButton, hostButton])
        statusStack.axis = .vertical
        statusStack.spacing = 10
        statusCard.addSubview(statusStack)
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusStack.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 14),
            statusStack.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 14),
            statusStack.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -14),
            statusStack.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -14)
        ])

        // Join Input Section
        joinInput.placeholder = "Nhập mã phòng (ví dụ: K7Q2-M9XD)"
        joinInput.font = .monospacedSystemFont(ofSize: 16, weight: .semibold)
        joinInput.textColor = .white
        joinInput.backgroundColor = UIColor(white: 0.18, alpha: 0.9)
        joinInput.layer.cornerRadius = 12
        joinInput.textAlignment = .center
        joinInput.autocapitalizationType = .allCharacters
        joinInput.autocorrectionType = .no
        joinInput.heightAnchor.constraint(equalToConstant: 44).isActive = true

        joinButton.addAction(UIAction { [weak self] _ in
            guard let self = self, let text = self.joinInput.text, !text.isEmpty else { return }
            self.roomManager.joinRoom(code: text)
            self.joinInput.resignFirstResponder()
            self.updateUI()
        }, for: .touchUpInside)

        leaveButton.addAction(UIAction { [weak self] _ in
            self?.roomManager.leaveRoom()
            self?.updateUI()
        }, for: .touchUpInside)

        startGameButton.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true) {
                self?.onPlayTapped?()
            }
        }, for: .touchUpInside)

        let joinRow = UIStackView(arrangedSubviews: [joinInput, joinButton])
        joinRow.axis = .vertical
        joinRow.spacing = 8

        // Main Layout
        let mainStack = UIStackView(arrangedSubviews: [header, statusCard, joinRow, startGameButton, leaveButton])
        mainStack.axis = .vertical
        mainStack.spacing = 14
        view.addSubview(mainStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            mainStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            mainStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24)
        ])
    }

    private func bindManager() {
        roomManager.onStateChanged = { [weak self] _ in
            DispatchQueue.main.async { self?.updateUI() }
        }
        roomManager.onPeersUpdated = { [weak self] peers in
            DispatchQueue.main.async {
                self?.playerList = peers
                self?.updateUI()
            }
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
            joinInput.isHidden = false
            joinButton.isHidden = false
            leaveButton.isHidden = true
            startGameButton.isHidden = true

        case .hosting(let code):
            statusLabel.text = "👑 BẠN LÀ CHỦ PHÒNG\nChia sẻ mã phòng này để bạn bè cùng tham gia:"
            roomCodeDisplay.text = code
            roomCodeDisplay.textColor = .systemGreen
            copyButton.isHidden = false
            hostButton.isHidden = true
            joinInput.isHidden = true
            joinButton.isHidden = true
            leaveButton.isHidden = false
            startGameButton.isHidden = false

        case .connecting(let code):
            statusLabel.text = "Đang kết nối tới phòng \(code)..."
            roomCodeDisplay.text = code
            roomCodeDisplay.textColor = .systemOrange
            copyButton.isHidden = true
            hostButton.isHidden = true
            joinInput.isHidden = true
            joinButton.isHidden = true
            leaveButton.isHidden = false
            startGameButton.isHidden = true

        case .connected(let code, let isHost):
            let count = playerList.count + 1
            statusLabel.text = "✅ ĐÃ KẾT NỐI PHÒNG (\(count) người chơi)\n\(isHost ? "Bạn là Host" : "Bạn là Khách tham gia")"
            roomCodeDisplay.text = code
            roomCodeDisplay.textColor = .systemGreen
            copyButton.isHidden = false
            hostButton.isHidden = true
            joinInput.isHidden = true
            joinButton.isHidden = true
            leaveButton.isHidden = false
            startGameButton.isHidden = false

        case .error(let msg):
            statusLabel.text = "❌ \(msg)"
            roomCodeDisplay.text = "LỖI"
            roomCodeDisplay.textColor = .systemRed
            copyButton.isHidden = true
            hostButton.isHidden = false
            joinInput.isHidden = false
            joinButton.isHidden = false
            leaveButton.isHidden = false
            startGameButton.isHidden = true
        }
    }
}
