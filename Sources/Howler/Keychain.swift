import Foundation
import Security

struct KeychainError: LocalizedError {
    let status: OSStatus
    var operation = "access"

    var errorDescription: String? {
        let context = "Keychain \(operation) (OSStatus \(status))"
        switch status {
        case errSecAuthFailed, errSecInteractionNotAllowed:
            return "\(context): access was denied or requires authorization. Open \(AppInfo.name) Settings and retry there. Do not reset your configuration."
        case errSecUserCanceled:
            return "\(context): authorization was cancelled."
        default: break
        }
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return "\(context): \(message)"
    }
}

/// API keys live in the login keychain as generic passwords
/// (service = bundle identifier, account = api-key:<destination scope>).
/// Older installations use api-key or a provider ID until migrated.
enum Keychain {
    struct Operations {
        var update: (CFDictionary, CFDictionary) -> OSStatus = SecItemUpdate
        var add: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus = SecItemAdd
        var delete: (CFDictionary) -> OSStatus = SecItemDelete
        var copy: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus = SecItemCopyMatching
    }

    private static var service: String { AppInfo.bundleIdentifier }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func set(_ value: String, account: String, operations: Operations = Operations()) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let updateStatus = operations.update(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            break
        default:
            // Access denial is not proof of an obsolete identity. Never delete a
            // credential to work around authorization or interaction failures.
            throw KeychainError(status: updateStatus, operation: "save")
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "\(AppInfo.name) API key (\(account))"
        let addStatus = operations.add(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus, operation: "save") }
    }

    static func get(account: String, operations: Operations = Operations()) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = operations.copy(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status, operation: "read") }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode, operation: "read")
        }
        return value
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
