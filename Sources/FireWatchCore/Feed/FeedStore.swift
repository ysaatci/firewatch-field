import Foundation

/// What the app shows: the feed's state with this device's pending commands on top.
public struct FieldState: Hashable, Sendable {
    /// The fire as the crew should see it, pending commands included.
    public var fire: FireState
    /// The feed's own time for ``fire``: scenario time with the simulator. Use it, not the
    /// device clock, for anything relative such as "seen 5 minutes ago".
    public var asOf: Date?
    public var connection: ConnectionStatus
    /// Device time of the last update from the feed, for "data is 3 minutes old" banners.
    public var receivedAt: Date?
    /// Commands made on this device that the feed hasn't confirmed yet.
    public var pendingCommands: [HotspotCommand]

    public static let empty = FieldState(
        fire: FireState(), asOf: nil, connection: .connecting, receivedAt: nil, pendingCommands: [])
}

/// Holds the feed's state and publishes what the app should show (D9).
///
/// Pending commands are replayed over the latest feed state on every change: an optimistic
/// rebase. A pending command the feed has meanwhile made impossible simply stops showing.
public actor FeedStore {
    private var base = FireState()
    private var asOf: Date?
    private var connection = ConnectionStatus.connecting
    private var receivedAt: Date?
    private var pending: [HotspotCommand] = []
    private let broadcast = Broadcast<FieldState>()
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    public var current: FieldState {
        var fire = base
        for command in pending { _ = try? fire.execute(command) }
        return FieldState(
            fire: fire, asOf: asOf, connection: connection, receivedAt: receivedAt, pendingCommands: pending)
    }

    /// The current state now, then every change. Slow readers only ever get the newest state.
    public nonisolated func states() -> AsyncStream<FieldState> {
        let (id, stream) = broadcast.subscribe(bufferingPolicy: .bufferingNewest(1))
        Task { await broadcast.yield(current, to: id) }
        return stream
    }

    /// Applies `feed`'s updates until the calling task is cancelled.
    public func follow(_ feed: any DetectionFeed) async {
        for await update in feed.updates() {
            apply(update)
        }
    }

    public func apply(_ update: FeedUpdate) {
        switch update {
        case .snapshot(let state, let time):
            base = state
            asOf = time
            receivedAt = now()
        case .events(let events):
            for event in events { base.apply(event) }
            if let latest = events.map(\.time).max() { asOf = max(asOf ?? latest, latest) }
            receivedAt = now()
        case .connection(let status):
            connection = status
        }
        publish()
    }

    /// Shows a cached state from an earlier run until the feed sends something newer.
    public func restore(_ cached: CachedFire) {
        base = cached.state
        asOf = cached.asOf
        receivedAt = cached.receivedAt
        publish()
    }

    /// The feed's own state, without pending commands, for caching: those are restored from
    /// the outbox instead, so nothing unconfirmed is ever saved as fact.
    public var cacheable: CachedFire? {
        asOf.map { CachedFire(state: base, asOf: $0, receivedAt: receivedAt) }
    }

    /// Replaces the commands shown optimistically on top of the feed's state.
    public func setPending(_ commands: [HotspotCommand]) {
        pending = commands
        publish()
    }

    private func publish() {
        guard broadcast.hasSubscribers else { return }
        broadcast.yield(current)
    }
}
