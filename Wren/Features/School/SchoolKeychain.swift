import Foundation
import Security

/// Keychain storage for the parts of the school configuration that are secrets.
///
/// The personal calendar URL carries a token that is, in effect, a password for
/// the child's timetable: anyone holding it can read it. `UserDefaults` is a
/// plain plist in the app container, so it belongs here instead — and nowhere
/// near the repo, which is public.
enum SchoolKeychain {
    private static let service = "au.wren.school.secret"

    static func set(_ value: String, for key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { delete(key); return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = Data(trimmed.utf8)
        // Readable after the first unlock, so a background refresh can reach it
        // without the device being awake and open.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(insert as CFDictionary, nil)
        if status != errSecSuccess {
            // `Logger.record`, not `Logger.shared`: this type is nonisolated so
            // a background refresh can reach the token without hopping actors.
            Logger.record(.error, "school", "keychain write failed (\(status))")
        }
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
