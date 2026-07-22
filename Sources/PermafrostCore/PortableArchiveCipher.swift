import CommonCrypto
import CryptoKit
import Foundation

/// Password-based encryption for portable export archives. This is deliberately separate
/// from the per-machine Keychain key used for normal concealed storage.
enum PortableArchiveCipher {
    static let saltByteCount = 16
    static let iterations: UInt32 = 600_000

    enum Error: LocalizedError {
        case weakPassphrase
        case keyDerivationFailed
        case authenticationFailed

        var errorDescription: String? {
            switch self {
            case .weakPassphrase:
                return "Use a passphrase of at least 12 characters."
            case .keyDerivationFailed:
                return "Could not derive the archive encryption key."
            case .authenticationFailed:
                return "The passphrase is incorrect or the archive is damaged."
            }
        }
    }

    static func makeSalt() -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<saltByteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    static func seal(_ plaintext: Data, passphrase: String, salt: Data, iterations: UInt32) throws -> Data {
        let key = try derivedKey(passphrase: passphrase, salt: salt, iterations: iterations)
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else {
            throw Error.authenticationFailed
        }
        return combined
    }

    static func open(_ ciphertext: Data, passphrase: String, salt: Data, iterations: UInt32) throws -> Data {
        do {
            let key = try derivedKey(passphrase: passphrase, salt: salt, iterations: iterations)
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key)
        } catch let error as Error {
            throw error
        } catch {
            throw Error.authenticationFailed
        }
    }

    private static func derivedKey(passphrase: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        guard passphrase.count >= 12 else { throw Error.weakPassphrase }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = passphrase.withCString { password in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2), password, strlen(password),
                    saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                    &bytes, bytes.count)
            }
        }
        guard status == kCCSuccess else { throw Error.keyDerivationFailed }
        return SymmetricKey(data: Data(bytes))
    }
}
