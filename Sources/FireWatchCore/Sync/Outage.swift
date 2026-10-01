import Foundation

/// A switchable loss of signal, so the offline behaviour can be shown and tested without a
/// server: while active, submissions fail as unavailable and the feed reports itself offline.
public final class Outage: @unchecked Sendable {
    private let lock = NSLock()
    private var active: Bool
    private let broadcast = Broadcast<Bool>()

    public init(active: Bool = false) {
        self.active = active
    }

    public var isActive: Bool {
        get { lock.withLock { active } }
        set {
            let changed = lock.withLock {
                let old = active
                active = newValue
                return old != newValue
            }
            if changed { broadcast.yield(newValue) }
        }
    }

    /// Whether the outage is active now, then every change.
    public func states() -> AsyncStream<Bool> {
        let (id, stream) = broadcast.subscribe(bufferingPolicy: .bufferingNewest(1))
        broadcast.yield(isActive, to: id)
        return stream
    }
}

/// A sink that can't get through during an ``Outage``.
public struct OutageSink: CommandSink {
    private let wrapped: any CommandSink
    private let outage: Outage

    public init(wrapping wrapped: any CommandSink, outage: Outage) {
        self.wrapped = wrapped
        self.outage = outage
    }

    public func submit(_ command: HotspotCommand) async throws(SubmissionError) -> SubmissionOutcome {
        guard !outage.isActive else { throw .unavailable }
        return try await wrapped.submit(command)
    }

    public func submit(_ report: SightingReport) async throws(SubmissionError) -> SubmissionOutcome {
        guard !outage.isActive else { throw .unavailable }
        return try await wrapped.submit(report)
    }
}

/// A feed that goes silent during an ``Outage`` and, like a real reconnect, starts over with
/// a fresh subscription (and so a fresh snapshot) when it ends.
public struct OutageFeed: DetectionFeed {
    private let wrapped: any DetectionFeed
    private let outage: Outage
    private let now: @Sendable () -> Date
    /// When the offline status says the next attempt is due.
    private let retryInterval: TimeInterval

    public init(
        wrapping wrapped: any DetectionFeed,
        outage: Outage,
        retryInterval: TimeInterval = 5,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.wrapped = wrapped
        self.outage = outage
        self.retryInterval = retryInterval
        self.now = now
    }

    public func updates() -> AsyncStream<FeedUpdate> {
        AsyncStream { continuation in
            let task = Task {
                var connection: Task<Void, Never>?
                for await active in outage.states() {
                    connection?.cancel()
                    if active {
                        continuation.yield(.connection(.offline(retryAt: now().addingTimeInterval(retryInterval))))
                    } else {
                        connection = Task {
                            for await update in wrapped.updates() { continuation.yield(update) }
                        }
                    }
                }
                connection?.cancel()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
