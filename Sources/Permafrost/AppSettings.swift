import Foundation
import PermafrostCore
import ServiceManagement

/// UserDefaults-backed settings. SwiftUI views bind via @AppStorage on the same keys;
/// this type is the single place that interprets raw values (e.g. into RetentionPolicy).
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    enum Keys {
        static let retentionDays = "retentionDays"  // 0 = keep forever
        static let maxUnpinnedCount = "maxUnpinnedCount"  // 0 = unlimited
        static let hotkeyPreset = "hotkeyPreset"
        static let recordConcealed = "recordConcealed"
        static let capturePaused = "capturePaused"
        static let maxImageMegabytes = "maxImageMegabytes"
        static let didShowWelcome = "didShowWelcome"
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Keys.retentionDays: 30,
            Keys.maxUnpinnedCount: 2000,
            Keys.hotkeyPreset: HotkeyPreset.optionCommandV.rawValue,
            Keys.recordConcealed: false,
            Keys.capturePaused: false,
            Keys.maxImageMegabytes: 10,
        ])
    }

    var retentionPolicy: RetentionPolicy {
        let days = defaults.integer(forKey: Keys.retentionDays)
        let cap = defaults.integer(forKey: Keys.maxUnpinnedCount)
        return RetentionPolicy(
            maxAge: days > 0 ? TimeInterval(days) * 24 * 60 * 60 : nil,
            maxUnpinnedCount: cap > 0 ? cap : nil
        )
    }

    var hotkeyPreset: HotkeyPreset {
        HotkeyPreset(rawValue: defaults.string(forKey: Keys.hotkeyPreset) ?? "")
            ?? .optionCommandV
    }

    var recordConcealed: Bool {
        defaults.bool(forKey: Keys.recordConcealed)
    }

    var capturePaused: Bool {
        get { defaults.bool(forKey: Keys.capturePaused) }
        set { defaults.set(newValue, forKey: Keys.capturePaused) }
    }

    var maxImageBytes: Int {
        max(1, defaults.integer(forKey: Keys.maxImageMegabytes)) * 1024 * 1024
    }

    var didShowWelcome: Bool {
        get { defaults.bool(forKey: Keys.didShowWelcome) }
        set { defaults.set(newValue, forKey: Keys.didShowWelcome) }
    }

    /// Login item state via SMAppService. Registration only works from a real .app
    /// bundle; during bare-executable development it fails harmlessly.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Log.app.error("launch-at-login change failed: \(error.localizedDescription)")
            }
        }
    }
}
