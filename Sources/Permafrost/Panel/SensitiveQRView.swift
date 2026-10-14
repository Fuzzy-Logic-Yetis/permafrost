import PermafrostCore
import SwiftUI

extension QRSensitiveStatus {
    var shortLabel: String {
        switch self {
        case .omitted: "Sensitive QR payload omitted"
        case .encrypted: "Sensitive QR payload encrypted"
        case .keyUnavailable: "Sensitive QR payload not saved"
        }
    }
}

/// Explicit reveal/copy keeps sensitive text out of ordinary OCR, drag and share paths.
struct SensitiveQRView: View {
    /// Collapses what were two independently-mutated `@State` variables (`revealedText:
    /// String?` and `unavailable: Bool`) into one (ADR-025) — `unavailable` was always
    /// exactly "a reveal attempt returned nil," so the two could only drift out of the
    /// three states they're meant to represent if a future call site updated one and not
    /// the other. One enum makes each transition a single assignment instead of two.
    private enum RevealState: Equatable {
        case hidden
        case revealed(String)
        case unavailable
    }

    let status: QRSensitiveStatus
    let encryptedData: Data?
    let reveal: () -> String?
    let copy: () -> Void
    @State private var revealState: RevealState = .hidden

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(status.shortLabel, systemImage: "lock.shield")
                .font(.headline)
            switch status {
            case .omitted:
                Text("An authenticator or Wi-Fi payload was omitted. To save future payloads, enable encrypted sensitive QR capture in Settings, then copy the image again.")
            case .keyUnavailable:
                Text("The Keychain key was unavailable, so the decoded secret was not saved. Allow Keychain access, then copy this image again.")
            case .encrypted:
                HStack {
                    Button(revealState == .hidden || revealState == .unavailable ? "Reveal Sensitive QR" : "Hide Sensitive QR") {
                        switch revealState {
                        case .hidden, .unavailable:
                            if let text = reveal() { revealState = .revealed(text) } else { revealState = .unavailable }
                        case .revealed:
                            revealState = .hidden
                        }
                    }
                    .keyboardShortcut("r", modifiers: [.option, .command])
                    .help("Reveal or hide sensitive QR (⌥⌘R)")
                    if case .revealed = revealState {
                        Button("Copy Sensitive QR", action: copy)
                            .keyboardShortcut("c", modifiers: [.shift, .command])
                            .help("Copy sensitive QR (⇧⌘C)")
                    }
                }
                Text({ if case .revealed(let text) = revealState { text } else { "••••••••••••" } }())
                    .font(.system(.body, design: .monospaced))
                if revealState == .unavailable {
                    Text("Cannot unlock this payload. Allow Keychain access and retry; a damaged backup may require restoring another copy.")
                        .foregroundStyle(.secondary)
                }
            }
            Text("The screenshot and visible OCR text remain ordinary history.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: encryptedData) { revealState = .hidden }
    }
}
