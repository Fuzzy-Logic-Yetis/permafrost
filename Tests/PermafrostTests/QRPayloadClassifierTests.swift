import Testing

@testable import Permafrost

@Suite struct QRPayloadClassifierTests {
    @Test func ordinaryURLIsRecorded() {
        #expect(QRPayloadClassifier.classify("https://example.com/menu") == .ordinary)
    }

    @Test func plainTextIsRecorded() {
        #expect(QRPayloadClassifier.classify("Table 14 — order code 8823") == .ordinary)
    }

    @Test func emptyPayloadIsOrdinary() {
        #expect(QRPayloadClassifier.classify("") == .ordinary)
    }

    @Test func authenticatorSetupKeyIsSensitive() {
        let payload = "otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example"
        #expect(QRPayloadClassifier.classify(payload) == .sensitive(.authenticatorSetupKey))
    }

    @Test func authenticatorBulkExportIsSensitive() {
        #expect(
            QRPayloadClassifier.classify("otpauth-migration://offline?data=CjEKCkhlbGxv")
                == .sensitive(.authenticatorSetupKey)
        )
    }

    @Test func wifiCredentialsAreSensitive() {
        #expect(
            QRPayloadClassifier.classify("WIFI:T:WPA;S:HomeNetwork;P:hunter2;;")
                == .sensitive(.wifiCredentials)
        )
    }

    /// Failing safe on an open network is the deliberate trade (ADR-022): treating every
    /// `WIFI:` payload as sensitive avoids parsing the format's escaping rules.
    @Test func passwordlessWiFiIsStillTreatedAsSensitive() {
        #expect(
            QRPayloadClassifier.classify("WIFI:T:nopass;S:GuestWiFi;;")
                == .sensitive(.wifiCredentials)
        )
    }

    /// URI schemes are case-insensitive (RFC 3986), and QR encoders disagree on the casing
    /// of the `WIFI:` prefix — a classifier that only matched one casing would leak.
    @Test func schemeMatchingIsCaseInsensitive() {
        #expect(
            QRPayloadClassifier.classify("OTPAUTH://TOTP/Example?secret=ABC")
                == .sensitive(.authenticatorSetupKey)
        )
        #expect(
            QRPayloadClassifier.classify("wifi:T:WPA;S:net;P:pw;;")
                == .sensitive(.wifiCredentials)
        )
    }

    @Test func surroundingWhitespaceDoesNotDefeatMatching() {
        #expect(
            QRPayloadClassifier.classify("  \n otpauth://totp/A?secret=B \n ")
                == .sensitive(.authenticatorSetupKey)
        )
    }

    /// A URL that merely mentions a sensitive scheme somewhere in its body is an ordinary
    /// link — only the payload's own scheme decides.
    @Test func schemeMustBeAtTheStartOfThePayload() {
        #expect(
            QRPayloadClassifier.classify("https://example.com/help?topic=otpauth://totp")
                == .ordinary
        )
    }
}
