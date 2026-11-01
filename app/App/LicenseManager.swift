import UIKit
import CryptoKit
import Security

/// Manages offline, device-bound license activation for Mugoat Nova.
/// Each device receives a unique 8-character Device ID derived from IDFV.
/// Keys are deterministic and verified offline via SHA-256 with a private salt.
final class LicenseManager {
    static let shared = LicenseManager()

    // Private salt for deterministic offline key generation.
    // Kept secret between the game engine, keygen app, and keygen script.
    private static let salt = "MugoatNova#2026@SecretLicenseSalt!"
    private static let keychainAccountKey = "mugoat_nova_license_key"
    private static let keychainAccountSig = "mugoat_nova_license_sig"
    private static let defaultsKey = "MugoatLicenseKey"
    private static let defaultsSig = "MugoatLicenseSignature"

    private init() {}

    /// Formatted 8-character Device ID: e.g. "0CD2-2316"
    var deviceId: String {
        let rawUUID = getPersistentDeviceUUID()
        return Self.formatDeviceId(rawUUID: rawUUID)
    }

    /// Whether this device currently has a valid, untampered license key.
    var isActivated: Bool {
        let devId = deviceId
        // Try Keychain first, fallback to UserDefaults
        let key = readKeychain(account: Self.keychainAccountKey) ?? UserDefaults.standard.string(forKey: Self.defaultsKey)
        let sig = readKeychain(account: Self.keychainAccountSig) ?? UserDefaults.standard.string(forKey: Self.defaultsSig)

        guard let key = key, let sig = sig else { return false }
        guard Self.verifySignature(deviceId: devId, key: key, signature: sig) else { return false }
        return Self.verifyKey(deviceId: devId, key: key)
    }

    /// Attempt to activate with the provided key string.
    /// Returns true if the key is valid for this device.
    @discardableResult
    func activate(key: String) -> Bool {
        let devId = deviceId
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard Self.verifyKey(deviceId: devId, key: trimmedKey) else {
            return false
        }

        let fullKey = trimmedKey.hasPrefix("NOVA-") ? trimmedKey : "NOVA-\(trimmedKey)"
        let sig = Self.computeSignature(deviceId: devId, key: fullKey)

        // Save to Keychain
        saveKeychain(account: Self.keychainAccountKey, value: fullKey)
        saveKeychain(account: Self.keychainAccountSig, value: sig)

        // Also save to UserDefaults as safe local backup
        UserDefaults.standard.set(fullKey, forKey: Self.defaultsKey)
        UserDefaults.standard.set(sig, forKey: Self.defaultsSig)
        UserDefaults.standard.synchronize()

        return true
    }

    /// Displays the activation modal dialog if not already activated.
    func showActivationModal(on presenter: UIViewController, onActivated: @escaping () -> Void) {
        if isActivated {
            onActivated()
            return
        }
        let modal = ActivationViewController()
        modal.onActivated = onActivated
        modal.modalPresentationStyle = .overFullScreen
        modal.modalTransitionStyle = .crossDissolve
        presenter.present(modal, animated: true)
    }

    // MARK: - Cryptographic Math

    static func formatDeviceId(rawUUID: String) -> String {
        let clean = rawUUID.replacingOccurrences(of: "-", with: "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let digest = sha256Hex(clean)
        let code = String(digest.prefix(8)).uppercased()
        let part1 = String(code.prefix(4))
        let part2 = String(code.suffix(4))
        return "\(part1)-\(part2)"
    }

    static func expectedKey(for deviceCode: String) -> String {
        let clean = deviceCode.replacingOccurrences(of: "NOVA-", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        let payload = "\(clean):\(salt)"
        let digest = sha256Hex(payload)
        // Take bytes 4..7 (index 8..16)
        let start = digest.index(digest.startIndex, offsetBy: 8)
        let end = digest.index(start, offsetBy: 8)
        let keySlice = String(digest[start..<end]).uppercased()
        let part1 = String(keySlice.prefix(4))
        let part2 = String(keySlice.suffix(4))
        return "NOVA-\(part1)-\(part2)"
    }

    static func verifyKey(deviceId: String, key: String) -> Bool {
        let expected = expectedKey(for: deviceId)
        var cleanInput = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !cleanInput.hasPrefix("NOVA-") {
            cleanInput = "NOVA-\(cleanInput)"
        }
        return cleanInput == expected
    }

    static func computeSignature(deviceId: String, key: String) -> String {
        let cleanId = deviceId.replacingOccurrences(of: "-", with: "").uppercased()
        let cleanKey = key.replacingOccurrences(of: "-", with: "").uppercased()
        let payload = "ACTIVATED:\(cleanId):\(cleanKey):\(salt)"
        return sha256Hex(payload)
    }

    static func verifySignature(deviceId: String, key: String, signature: String) -> Bool {
        let expected = computeSignature(deviceId: deviceId, key: key)
        return signature.caseInsensitiveCompare(expected) == .orderedSame
    }

    private static func sha256Hex(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    // MARK: - Persistent Storage

    private func getPersistentDeviceUUID() -> String {
        let account = "mugoat_device_seed"
        if let existing = readKeychain(account: account), !existing.isEmpty {
            return existing
        }
        let fallback = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        saveKeychain(account: account, value: fallback)
        return fallback
    }

    private func saveKeychain(account: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func readKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
