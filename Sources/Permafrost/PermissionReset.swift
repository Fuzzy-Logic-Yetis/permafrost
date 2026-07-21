import Foundation

/// Ad-hoc signed builds get a new code identity every re-sign (ADR-013/014, docs/TESTING.md):
/// a TCC grant can end up tied to a *previous* build's signature while System Settings still
/// displays "Permafrost" as checked, so `AXIsProcessTrusted`/`IOHIDCheckAccess` honestly report
/// not-granted despite the misleading checkbox (ADR-016). `tccutil reset` needs no special
/// privileges to clear an app's own grants for the current user — this makes that self-service
/// from within the app instead of requiring Terminal.
enum PermissionReset {
    static let bundleID = "com.fuzzylogicyetis.Permafrost"

    private static let services: [(tccName: String, displayName: String)] = [
        ("Accessibility", "Accessibility"),
        ("ListenEvent", "Input Monitoring"),
    ]

    /// Runs off the main actor (review L-3) — `tccutil` is normally instant, but
    /// nothing guarantees that, and this was previously blocking the UI thread
    /// from inside a Settings alert action.
    ///
    /// Returns a display-name → message entry for each service `tccutil` failed to reset, so
    /// callers can tell the user instead of assuming success. A non-zero exit (e.g. no matching
    /// TCC record) previously looked identical to a real reset — only `Process.run()` throwing
    /// (binary missing) was treated as failure.
    static func resetAccessibilityAndInputMonitoring() async -> [(service: String, message: String)] {
        await Task.detached(priority: .userInitiated) {
            var failures: [(service: String, message: String)] = []
            for (tccName, displayName) in services {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                process.arguments = ["reset", tccName, bundleID]
                let stderrPipe = Pipe()
                process.standardError = stderrPipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else {
                        let output = String(
                            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8
                        )?.trimmingCharacters(in: .whitespacesAndNewlines)
                        let message = (output?.isEmpty == false ? output! : nil)
                            ?? "exited with status \(process.terminationStatus)"
                        Log.app.error(
                            "tccutil reset \(tccName, privacy: .public) \(message, privacy: .public)"
                        )
                        failures.append((displayName, message))
                        continue
                    }
                } catch {
                    Log.app.error(
                        "tccutil reset \(tccName, privacy: .public) failed: \(error.localizedDescription)"
                    )
                    failures.append((displayName, error.localizedDescription))
                }
            }
            return failures
        }.value
    }
}
