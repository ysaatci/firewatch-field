import Foundation

/// Fans values out to any number of `AsyncStream` subscribers. Subscribers that stop
/// listening are forgotten automatically. Safe to use from any isolation domain.
public final class Broadcast<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    public init() {}

    public var hasSubscribers: Bool { lock.withLock { !continuations.isEmpty } }

    /// A new subscription and its ID, for addressing it with ``yield(_:to:)``. `onTermination`
    /// runs once the subscriber stops listening.
    public func subscribe(
        bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded,
        onTermination: @escaping @Sendable () -> Void = {}
    ) -> (id: UUID, stream: AsyncStream<Element>) {
        let (stream, continuation) = AsyncStream.makeStream(of: Element.self, bufferingPolicy: bufferingPolicy)
        let id = UUID()
        lock.withLock { continuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.remove(id)
            onTermination()
        }
        return (id, stream)
    }

    /// Sends `element` to every subscriber.
    public func yield(_ element: Element) {
        for continuation in lock.withLock({ Array(continuations.values) }) { continuation.yield(element) }
    }

    /// Sends `element` to one subscriber, if it is still listening.
    public func yield(_ element: Element, to id: UUID) {
        lock.withLock { continuations[id] }?.yield(element)
    }

    private func remove(_ id: UUID) {
        lock.withLock { continuations[id] = nil }
    }
}
