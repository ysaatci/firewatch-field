import Foundation

/// A clock tests move by hand.
public final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    public init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        current = start
    }

    public var now: Date { lock.withLock { current } }

    public func advance(seconds: Double) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// A stand-in for `Task.sleep` that only returns when the test calls ``release()``.
/// Cancelling a sleeper throws `CancellationError`, like `Task.sleep`.
public actor ManualSleeper {
    private var sleepers: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private var order: [UUID] = []
    private var banked = 0

    public init() {}

    /// How many tasks are waiting.
    public var waiting: Int { order.count }

    /// Suitable for injecting wherever code takes a `sleep` closure.
    public nonisolated func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await wait(id)
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func wait(_ id: UUID) async throws {
        if banked > 0 {
            banked -= 1
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            sleepers[id] = continuation
            order.append(id)
        }
    }

    /// Wakes the longest-waiting sleeper, or lets the next sleep return at once.
    public func release() {
        guard let id = order.first else {
            banked += 1
            return
        }
        order.removeFirst()
        sleepers.removeValue(forKey: id)?.resume()
    }

    private func cancel(_ id: UUID) {
        order.removeAll { $0 == id }
        sleepers.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}
