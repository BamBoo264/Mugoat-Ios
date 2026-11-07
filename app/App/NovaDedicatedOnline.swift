import UIKit

enum NovaDedicatedOnline {
    private static let prefs = UserDefaults.standard
    static var endpoint: String { prefs.string(forKey: "NovaDedicatedEndpoint") ?? "" }
    static var enabled: Bool { prefs.bool(forKey: "NovaDedicatedEnabled") }
    static var room: String { prefs.string(forKey: "NovaDedicatedRoom") ?? "nova-city" }
    static var pvp: Bool { prefs.object(forKey: "NovaDedicatedPvP") as? Bool ?? true }

    static func configure() -> Bool {
        guard enabled else { return true }
        let name = OnlineRoomManager.shared.localPlayerName
        return endpoint.withCString { address in
            name.withCString { player in
                room.withCString { roomName in
                    MugoatOnlineConfigure(address, player, roomName, 0, pvp)
                }
            }
        }
    }

    static func show(on controller: UIViewController, completion: @escaping () -> Void) {
        let title = "Server UDP R007"
        let alert = UIAlertController(title: title,
            message: "Dùng địa chỉ máy đang chạy mugoat-server, ví dụ 192.168.1.10:47520. Hai máy chọn cùng phòng và chế độ PvP. Chọn Tự do ở launcher trước khi chơi.",
            preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "IP hoặc tên máy:47520"
            field.text = endpoint
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addTextField { field in
            field.placeholder = "Tên phòng"
            field.text = room
            field.autocorrectionType = .no
        }
        func set(_ allowPvP: Bool) {
            let host = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty, host.utf8.count <= 253, !host.contains(where: \.isWhitespace) else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let invalid = UIAlertController(title: title, message: "Nhập địa chỉ server UDP hợp lệ.", preferredStyle: .alert)
                    invalid.addAction(UIAlertAction(title: "OK", style: .default))
                    controller.present(invalid, animated: true)
                }
                return
            }
            let roomName = (alert.textFields?.last?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            prefs.set(host, forKey: "NovaDedicatedEndpoint")
            prefs.set(roomName.isEmpty ? "nova-city" : String(roomName.prefix(32)), forKey: "NovaDedicatedRoom")
            prefs.set(allowPvP, forKey: "NovaDedicatedPvP")
            prefs.set(true, forKey: "NovaDedicatedEnabled")
            OnlineRoomManager.shared.leaveRoom()
            completion()
        }
        alert.addAction(UIAlertAction(title: "Dùng UDP, bật PvP", style: .default) { _ in set(true) })
        alert.addAction(UIAlertAction(title: "Dùng UDP, tắt PvP", style: .default) { _ in set(false) })
        alert.addAction(UIAlertAction(title: "Dùng lại Nova City", style: .default) { _ in
            prefs.set(false, forKey: "NovaDedicatedEnabled")
            completion()
        })
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        controller.present(alert, animated: true)
    }
}
