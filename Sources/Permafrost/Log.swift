import os

/// Central loggers. Never log clipboard *content* (CLAUDE.md security principles).
enum Log {
    static let app = Logger(subsystem: "com.fuzzylogicyetis.Permafrost", category: "app")
    static let capture = Logger(subsystem: "com.fuzzylogicyetis.Permafrost", category: "capture")
    static let store = Logger(subsystem: "com.fuzzylogicyetis.Permafrost", category: "store")
}
