import Foundation

/// The last known fire state, kept on the device so the app opens with data even before the
/// feed answers, and stays useful offline (FR-9, NFR-2, NFR-3).
public protocol FieldCache: Sendable {
    func load() async -> CachedFire?
    func save(_ fire: CachedFire) async
}

/// A saved fire state and the feed time it was valid for.
public struct CachedFire: Hashable, Sendable {
    public var state: FireState
    public var asOf: Date
    /// Device time the feed last sent anything, restored so data age stays honest.
    public var receivedAt: Date?

    public init(state: FireState, asOf: Date, receivedAt: Date? = nil) {
        self.state = state
        self.asOf = asOf
        self.receivedAt = receivedAt
    }
}

/// Keeps the cache in memory only, for tests and previews.
public actor InMemoryFieldCache: FieldCache {
    public private(set) var saved: CachedFire?
    public private(set) var saveCount = 0

    public init(_ saved: CachedFire? = nil) {
        self.saved = saved
    }

    public func load() -> CachedFire? { saved }

    public func save(_ fire: CachedFire) {
        saved = fire
        saveCount += 1
    }
}
