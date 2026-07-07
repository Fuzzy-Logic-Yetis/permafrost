import Foundation

/// Ad-hoc signed builds get a new code identity every re-sign (ADR-013/014, docs/TESTING.md):
/// a TCC grant can end up tied to a *previous* build's signature while System Settings still
/// displays "Permafrost" as checked, so `AXIsProcessTrusted`/`IOHIDCheckAccess` honestly report
/// not-granted despite the misleading checkbox (ADR-016). `tccutil reset` needs no special
/// privileges to clear an app's own grants for the current user — this makes that self-service
/// from within the app instead of requiring Terminal.
@MainActor
enum PermissionReset {
    static let bundleID = "com.fuzzylogicyetis.Permafrost"

    static func resetAccessibilityAndInputMonitoring() {
        for service in ["Accessibility", "ListenEvent"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", service, bundleID]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                Log.app.error(
                    "tccutil reset \(service, privacy: .public) failed: \(error.localizedDescription)"
                )
            }
        }
    }
}
