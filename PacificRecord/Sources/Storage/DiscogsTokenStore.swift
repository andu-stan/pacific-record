import Foundation
import Security

/// The Discogs personal access token — the one real secret this app holds.
///
/// It grants read *and write* access to the owner's Discogs collection,
/// wantlist and marketplace, so it lives in the keychain rather than
/// `UserDefaults`: a defaults plist is plain text inside the app container and
/// rides along in unencrypted device backups. `…ThisDeviceOnly` keeps the
/// keychain item out of backups entirely, and `…WhenUnlocked` is enough because
/// nothing here runs while the device is locked.
///
/// Reads happen from background tasks (value refresh, collection import), so
/// this is a plain thread-safe type rather than an actor or a main-actor model.
enum DiscogsTokenStore {
    private static let service = "ro.sofistic.pacificrecord"
    private static let account = "discogs-token"
    /// Where the token used to live. Read once, then wiped.
    private static let legacyDefaultsKey = "discogsToken"

    private static let lock = NSLock()
    private static var cached: String?

    /// The stored token, or an empty string when none is set.
    static func read() -> String {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }

        let value = migrateFromDefaults() ?? keychainRead() ?? ""
        cached = value
        return value
    }

    /// Saves (or, given an empty string, clears) the token.
    static func write(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        keychainWrite(trimmed)
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
        cached = trimmed
    }

    // MARK: - Internals

    /// Moves a token written by an earlier build out of the defaults plist.
    /// Returns it when there was one, so the first read doesn't have to bounce
    /// off the keychain it just wrote.
    private static func migrateFromDefaults() -> String? {
        let defaults = UserDefaults.standard
        guard let legacy = defaults.string(forKey: legacyDefaultsKey) else { return nil }
        defaults.removeObject(forKey: legacyDefaultsKey)
        let trimmed = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        keychainWrite(trimmed)
        return trimmed
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func keychainRead() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    /// Delete-then-add rather than update: one code path, and it doubles as the
    /// clear operation when the token is empty.
    private static func keychainWrite(_ token: String) {
        SecItemDelete(baseQuery as CFDictionary)
        guard !token.isEmpty else { return }
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
