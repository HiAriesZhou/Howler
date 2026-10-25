import Foundation
import Security

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "Keychain: \(message)"
    }
}

/// API keys live in the login keychain as generic passwords
/// (service = bundle identifier, account = provider id).
enum Keychain {
    private static var service: String { AppInfo.bundleIdentifier }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError(status: updateStatus) }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "\(AppInfo.name) API key (\(account))"
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    static func get(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Checks presence via attributes only, which never triggers a keychain access prompt.
    static func exists(account: String) -> Bool {
        var query = baseQuery(account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
