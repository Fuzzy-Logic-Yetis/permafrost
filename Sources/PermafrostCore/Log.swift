import os

/// Internal-only diagnostics for this module. PermafrostCore stays headless (no AppKit),
/// but still follows CLAUDE.md's "os.Logger only, never log clipboard content" rule for
/// its own failures that don't propagate up as a thrown error for the app layer to log.
enum Log {
    static let store = Logger(subsystem: "com.fuzzylogicyetis.Permafrost", category: "core.store")
}
