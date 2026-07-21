import CryptoKit
import Foundation
import Security

/// Retrieves (or creates, on first use) the persistent Keychain-backed key used to encrypt
/// concealed items (ADR-021). `kSecAttrAccessibleWhenUnlocked` means decryption only works
/// while the Mac is unlocked. Keychain errors are deliberately surfaced instead of falling
/// back to an in-memory key: ciphertext must never be created with a key that was not stored.
enum ConcealedContentKeychain {
    enum KeychainError: LocalizedError {
        case read(OSStatus)
        case write(OSStatus)
        case invalidKeyData

        var errorDescription: String? {
            switch self {
            case .read(let status): return "Could not read concealed-content key (status \(status))."
            case .write(let status): return "Could not store concealed-content key (status \(status))."
            case .invalidKeyData: return "The concealed-content key has invalid data."
            }
        }
    }

    private static let service = "com.fuzzylogicyetis.Permafrost.concealedContentKey"
    private static let account = "concealedContentKey"

    static func loadOrCreateKey(
        completion: @escaping @Sendable (Result<SymmetricKey, KeychainError>) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            do {
                completion(.success(try loadOrCreateKeySynchronously()))
            } catch let error as KeychainError {
                completion(.failure(error))
            } catch {
                assertionFailure("Unexpected concealed-content Keychain error: \(error)")
                completion(.failure(.read(errSecInternalError)))
            }
        }
    }

    private static func loadOrCreateKeySynchronously() throws -> SymmetricKey {
        switch try loadKey() {
        case .some(let key):
            return key
        case nil:
            return try generateAndStoreKey()
        }
    }

    /// `nil` means only "not found". All other statuses are actionable failures, not an
    /// invitation to generate another key.
    private static func loadKey() throws -> SymmetricKey? {
        let query = itemQuery(returnData: true)
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            Log.store.error("Concealed-content Keychain read failed: status \(status, privacy: .public)")
            throw KeychainError.read(status)
        }
        guard data.count == 32 else {
            Log.store.error("Concealed-content Keychain contains invalid key data")
            throw KeychainError.invalidKeyData
        }
        return SymmetricKey(data: data)
    }

    private static func generateAndStoreKey() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        var attributes = itemQuery(returnData: false)
        attributes[kSecValueData as String] = keyData
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess { return key }
        if status == errSecDuplicateItem, let existing = try loadKey() { return existing }
        Log.store.error("Concealed-content Keychain write failed: status \(status, privacy: .public)")
        throw KeychainError.write(status)
    }

    private static func itemQuery(returnData: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if returnData { query[kSecReturnData as String] = true }
        return query
    }
}
