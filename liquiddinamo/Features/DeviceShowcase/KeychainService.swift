//
//  KeychainService.swift
//  boringNotch
//
//  Created for Boring Notch
//

import Foundation
import Security

/// Secure Keychain wrapper for storing sensitive cloud API keys.
/// Uses macOS Keychain Services (kSecClassGenericPassword).
/// Keys are never logged, printed, or saved in plain text files.
public final class KeychainService {
    public static let shared = KeychainService()

    public static let defaultService = "com.agrigence.liquiddynamo.apikeys"
    public static let meshyAccount = "meshy_api_key"

    private let service: String

    public init(service: String = KeychainService.defaultService) {
        self.service = service
    }

    // MARK: - Meshy API Key Helper

    public func getMeshyKey() -> String? {
        return getKey(account: Self.meshyAccount)
    }

    public func setMeshyKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return deleteKey(account: Self.meshyAccount)
        }
        return saveKey(secret: trimmed, account: Self.meshyAccount)
    }

    public func hasMeshyKey() -> Bool {
        guard let key = getMeshyKey() else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func deleteMeshyKey() -> Bool {
        return deleteKey(account: Self.meshyAccount)
    }

    // MARK: - Core Keychain Operations

    public func saveKey(secret: String, account: String) -> Bool {
        guard let data = secret.data(using: .utf8) else { return false }

        // Remove existing item if present
        deleteKey(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    public func getKey(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let secret = String(data: data, encoding: .utf8) else {
            return nil
        }

        return secret
    }

    @discardableResult
    public func deleteKey(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
