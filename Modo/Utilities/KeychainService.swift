import Foundation
import Security

enum KeychainService {
    private static let service = "com.modo.app"

    @discardableResult
    static func saveKey(_ key: String, for account: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return deleteKey(for: account) }
        guard let data = trimmed.data(using: .utf8) else { return false }
        deleteKey(for: account)
        let query: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    service,
            kSecAttrAccount as String:    account,
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func loadKey(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    @discardableResult
    static func deleteKey(for account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func hasKey(for account: String) -> Bool {
        guard let key = loadKey(for: account) else { return false }
        return !key.isEmpty
    }

    // MARK: - Legacy Groq convenience (keeps old call sites compiling)

    @discardableResult
    static func saveAPIKey(_ key: String) -> Bool { saveKey(key, for: "groq-api-key") }
    static func loadAPIKey() -> String?           { loadKey(for: "groq-api-key") }
    @discardableResult
    static func deleteAPIKey() -> Bool            { deleteKey(for: "groq-api-key") }
    static var hasAPIKey: Bool                    { hasKey(for: "groq-api-key") }
}
