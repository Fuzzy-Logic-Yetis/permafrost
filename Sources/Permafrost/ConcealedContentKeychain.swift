import CryptoKit
import Foundation
import Security

/// Retrieves (or creates, on first use) the persistent Keychain-backed key used to encrypt
/// concealed items (ADR-021). `kSecAttrAccessibleWhenUnlocked` — decryption only works while
/// the Mac is unlocked.
///
/// ADR-021's spike found that reading a Keychain item whose access control doesn't
/// recognize the calling binary's exact code signature (any ad-hoc rebuild, in this
/// project's dev cycle) triggers a blocking, modal `SecurityAgent` authorization prompt
/// with **no built-in timeout** — it can hang the calling thread indefinitely.
///
/// *Revised 2026-07-21* (found live, not just in the lab): the original design bounded
/// that wait with a timeout and fell back to a fresh, never-persisted `SymmetricKey` if it
/// was hit — which meant a session that fell back silently encrypted real content with a
/// key that could never survive that process exiting. It destroyed a real concealed item
/// this way. There is now **no timeout and no fallback key** — the fetch runs entirely on
/// a background queue and calls back whenever it resolves, however long that takes, so
/// nothing is ever sealed with anything but the one real, persistent key. Until the
/// completion fires, `ClipboardStore` has no cipher at all and concealed-content
/// operations simply aren't available yet (`ClipboardStore.ConcealedContentError
/// .keyNotYetAvailable`) — never silently insecure, never silently unrecoverable.
enum ConcealedContentKeychain {
    private static let service = "com.fuzzylogicyetis.Permafrost.concealedContentKey"
    private static let account = "concealedContentKey"

    static func loadOrCreateKey(completion: @escaping @Sendable (SymmetricKey) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let key = loadKey() ?? generateAndStoreKey()
            completion(key)
        }
    }

    private static func loadKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                Log.store.error(
                    "Concealed-content Keychain read failed: status \(status, privacy: .public)")
            }
            return nil
        }
        return SymmetricKey(data: data)
    }

    private static func generateAndStoreKey() -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        var attributes = query
        attributes[kSecValueData as String] = keyData
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            Log.store.error(
                "Concealed-content Keychain write failed: status \(status, privacy: .public)")
        }
        return key
    }
}
