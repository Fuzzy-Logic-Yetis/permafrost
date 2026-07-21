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
/// with **no built-in timeout** — it can hang the calling thread indefinitely. The actual
/// read/write always happens on a background queue with a bounded wait, so a launch is
/// never stuck indefinitely on a dialog most users won't recognize; if the bound is hit,
/// this session falls back to an ephemeral, session-only key rather than freezing.
enum ConcealedContentKeychain {
    private static let service = "com.fuzzylogicyetis.Permafrost.concealedContentKey"
    private static let account = "concealedContentKey"

    static func loadOrCreateKey(timeout: TimeInterval = 2.0) -> SymmetricKey {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        DispatchQueue.global(qos: .utility).async {
            box.key = loadKey() ?? generateAndStoreKey()
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            Log.store.error(
                "Concealed-content Keychain key fetch exceeded \(timeout, privacy: .public)s (likely a stale ad-hoc signature awaiting reauthorization) — using a session-only key so launch isn't blocked indefinitely"
            )
            return SymmetricKey(size: .bits256)
        }
        return box.key ?? SymmetricKey(size: .bits256)
    }

    private final class ResultBox: @unchecked Sendable {
        var key: SymmetricKey?
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
