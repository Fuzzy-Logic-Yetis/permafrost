import Foundation

/// Decides whether a decoded QR payload is a *known* secret-bearing format that must not be
/// recorded as searchable plaintext (ADR-022).
///
/// Screen snips never carry the pasteboard's `org.nspasteboard.ConcealedType` marker, so the
/// ADR-011 concealed path can't see them: without this gate, snipping a 2FA enrollment screen
/// would silently write an authenticator seed into the history database in the clear.
///
/// This is deliberately an allowlist of well-defined secret formats, **not** a general secret
/// detector. A payload that happens to contain a password in some bespoke format is
/// indistinguishable from an ordinary URL and will be recorded normally — the honest limit of
/// this approach, documented in ADR-022 and docs/SECURITY.md.
enum QRPayloadClassifier {
    enum SensitiveReason: String, Equatable, Sendable {
        /// `otpauth:` / `otpauth-migration:` — carries the TOTP/HOTP shared secret itself,
        /// so recording it is equivalent to recording the user's second factor.
        case authenticatorSetupKey
        /// `WIFI:` — the standard join-network format, whose `P:` field is the passphrase.
        case wifiCredentials
    }

    enum Classification: Equatable, Sendable {
        case ordinary
        case sensitive(SensitiveReason)
    }

    /// URI schemes are case-insensitive (RFC 3986) and encoders vary on the `WIFI:` prefix,
    /// so matching is case-insensitive and tolerant of surrounding whitespace.
    static func classify(_ payload: String) -> Classification {
        let normalized = payload.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.hasPrefix("otpauth:") || normalized.hasPrefix("otpauth-migration:") {
            return .sensitive(.authenticatorSetupKey)
        }
        // Every `WIFI:` payload is treated as sensitive, including a passwordless open
        // network (`T:nopass`). Parsing the field grammar to tell them apart means handling
        // its backslash-escaping rules for a payload that is rarely worth keeping anyway;
        // failing safe on a guest-network QR is the cheaper mistake.
        if normalized.hasPrefix("wifi:") {
            return .sensitive(.wifiCredentials)
        }
        return .ordinary
    }
}
