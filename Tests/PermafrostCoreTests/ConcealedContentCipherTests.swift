import CryptoKit
import Foundation
import Testing

@testable import PermafrostCore

// ADR-021: ConcealedContentCipher doesn't exist yet — intentionally red on this branch
// (feat/concealed-encryption) until implemented.
@Suite struct ConcealedContentCipherTests {
    @Test func sealThenOpenRoundTripsToOriginalText() throws {
        let cipher = ConcealedContentCipher(key: SymmetricKey(size: .bits256))

        let sealed = try cipher.seal("hunter2-but-longer-and-actually-secure")
        let opened = try cipher.open(sealed)

        #expect(opened == "hunter2-but-longer-and-actually-secure")
    }

    @Test func openingWithWrongKeyFails() throws {
        let sealed = try ConcealedContentCipher(key: SymmetricKey(size: .bits256))
            .seal("my recognizable-but-not-memorizable password")
        let wrongKeyCipher = ConcealedContentCipher(key: SymmetricKey(size: .bits256))

        #expect(throws: (any Error).self) {
            try wrongKeyCipher.open(sealed)
        }
    }

    @Test func sealingTheSamePlaintextTwiceProducesDifferentCiphertext() throws {
        let cipher = ConcealedContentCipher(key: SymmetricKey(size: .bits256))

        let first = try cipher.seal("same password")
        let second = try cipher.seal("same password")

        #expect(first != second)
    }
}
