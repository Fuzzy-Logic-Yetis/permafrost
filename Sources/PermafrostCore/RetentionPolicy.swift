import Foundation

/// Pinned entries never expire — that guarantee lives in the purge SQL
/// (`WHERE is_pinned = 0`), not here. This policy only governs unpinned entries.
public struct RetentionPolicy: Equatable, Sendable {
    /// Unpinned entries unused for longer than this are purged. `nil` = keep forever.
    public var maxAge: TimeInterval?
    /// Upper bound on unpinned entries; oldest (by last use) beyond it are purged.
    /// `nil` = unlimited.
    public var maxUnpinnedCount: Int?

    public init(maxAge: TimeInterval? = nil, maxUnpinnedCount: Int? = nil) {
        self.maxAge = maxAge
        self.maxUnpinnedCount = maxUnpinnedCount
    }

    public static let `default` = RetentionPolicy(
        maxAge: 30 * 24 * 60 * 60,
        maxUnpinnedCount: 2000
    )

    public func cutoffDate(now: Date) -> Date? {
        maxAge.map { now.addingTimeInterval(-$0) }
    }
}
