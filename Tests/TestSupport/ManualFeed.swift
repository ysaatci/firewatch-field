import FireWatchCore

/// A feed the test drives: every subscriber receives whatever ``send(_:)`` is given.
public final class ManualFeed: DetectionFeed, @unchecked Sendable {
    private let broadcast = Broadcast<FeedUpdate>()

    public init() {}

    public var hasSubscribers: Bool { broadcast.hasSubscribers }

    public func updates() -> AsyncStream<FeedUpdate> {
        broadcast.subscribe().stream
    }

    public func send(_ update: FeedUpdate) {
        broadcast.yield(update)
    }
}
