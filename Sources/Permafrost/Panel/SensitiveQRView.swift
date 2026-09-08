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
    let status: QRSensitiveStatus
    let encryptedData: Data?
    let reveal: () -> String?
    let copy: () -> Void
    @State private var revealedText: String?
    @State private var unavailable = false

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
                    Button(revealedText == nil ? "Reveal Sensitive QR" : "Hide Sensitive QR") {
                        if revealedText != nil { revealedText = nil; unavailable = false }
                        else { revealedText = reveal(); unavailable = revealedText == nil }
                    }
                    .keyboardShortcut("r", modifiers: [.option, .command])
                    .help("Reveal or hide sensitive QR (⌥⌘R)")
                    if revealedText != nil {
                        Button("Copy Sensitive QR", action: copy)
                            .keyboardShortcut("c", modifiers: [.shift, .command])
                            .help("Copy sensitive QR (⇧⌘C)")
                    }
                }
                Text(revealedText ?? "••••••••••••")
                    .font(.system(.body, design: .monospaced))
                if unavailable {
                    Text("Cannot unlock this payload. Allow Keychain access and retry; a damaged backup may require restoring another copy.")
                        .foregroundStyle(.secondary)
                }
            }
            Text("The screenshot and visible OCR text remain ordinary history.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: encryptedData) { revealedText = nil; unavailable = false }
    }
}
