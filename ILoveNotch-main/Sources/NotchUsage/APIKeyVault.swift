// SPDX-License-Identifier: MIT
import Foundation
import Security

/// API keys pasted into Settings, kept in the login keychain under the name of the variable the
/// provider reads, like `OPENROUTER_API_KEY`. The providers see a saved key the way they see one a
/// shell exports (`ProcessEnvironmentReader`), so no key is ever written to a file.
enum APIKeyVault {
    /// The variables a saved key can stand in for; nothing else reaches the keychain.
    static var names: Set<String> { Set(UsageFeature.apiKeyNames.values) }

    private static let service = "ILoveNotch AI Usage"

    /// Only the app itself uses its keychain items. Another process asking for one, such as a test
    /// runner, would make macOS ask the user.
    private static let available = Bundle.main.bundleURL.pathExtension == "app"

    static func key(named name: String) -> String? {
        guard available else { return nil }
        var query = item(named: name)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data
        else { return nil }
        let key = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    static func save(_ key: String, named name: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard available, !trimmed.isEmpty else { throw VaultError.unavailable }
        SecItemDelete(item(named: name) as CFDictionary)
        var add = item(named: name)
        add[kSecValueData as String] = Data(trimmed.utf8)
        add[kSecAttrLabel as String] = "\(service): \(name)"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
    }

    static func delete(named name: String) {
        guard available else { return }
        SecItemDelete(item(named: name) as CFDictionary)
    }

    private static func item(named name: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]
    }

    enum VaultError: LocalizedError {
        case unavailable
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unavailable: "Paste a key first."
            case .keychain(let status):
                (SecCopyErrorMessageString(status, nil) as String?) ?? "The keychain didn't save the key (\(status))."
            }
        }
    }
}
