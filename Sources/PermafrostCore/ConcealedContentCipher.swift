import CryptoKit
import Foundation

/// Encrypts/decrypts concealed (password) item content (ADR-021). AES-GCM via CryptoKit;
/// the key itself is Keychain-backed in the `Permafrost` executable, injected here as a
/// plain `SymmetricKey` so this stays testable without touching the real Keychain.
struct ConcealedContentCipher {
    let key: SymmetricKey

    enum CipherError: Error {
        case sealingProducedNoCombinedRepresentation
        case decryptedDataWasNotValidUTF8
    }

    /// A fresh nonce is used every call (CryptoKit's default) — sealing the same
    /// plaintext twice must never produce the same ciphertext.
    func seal(_ plaintext: String) throws -> Data {
        let sealedBox = try AES.GCM.seal(Data(plaintext.utf8), using: key)
        guard let combined = sealedBox.combined else {
            throw CipherError.sealingProducedNoCombinedRepresentation
        }
        return combined
    }

    func open(_ data: Data) throws -> String {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let plaintextData = try AES.GCM.open(sealedBox, using: key)
        guard let text = String(data: plaintextData, encoding: .utf8) else {
            throw CipherError.decryptedDataWasNotValidUTF8
        }
        return text
    }
}
