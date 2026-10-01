import Foundation

/// Something waiting to be sent.
public enum OutboxItem: Hashable, Sendable {
    case command(HotspotCommand)
    case report(SightingReport)

    /// The client-generated ID the server uses to recognise retries.
    public var id: String {
        switch self {
        case .command(let command): command.id.rawValue
        case .report(let report): report.id.rawValue
        }
    }
}

/// A queued item and how sending it has gone so far.
public struct OutboxEntry: Hashable, Sendable {
    public var item: OutboxItem
    public var enqueuedAt: Date
    /// Failed attempts so far.
    public var attempts: Int

    public init(item: OutboxItem, enqueuedAt: Date, attempts: Int = 0) {
        self.item = item
        self.enqueuedAt = enqueuedAt
        self.attempts = attempts
    }
}

/// Where queued items are kept so they survive the app being killed (NFR-3).
public protocol OutboxStore: Sendable {
    func load() async throws -> [OutboxEntry]
    func save(_ entries: [OutboxEntry]) async throws
}

/// Keeps entries in memory only, for tests and previews.
public actor InMemoryOutboxStore: OutboxStore {
    private var entries: [OutboxEntry]

    public init(_ entries: [OutboxEntry] = []) {
        self.entries = entries
    }

    public func load() -> [OutboxEntry] { entries }
    public func save(_ entries: [OutboxEntry]) { self.entries = entries }
}

/// What the outbox reports to the app.
public enum OutboxEvent: Hashable, Sendable {
    /// The queue changed; these are still waiting, oldest first.
    case pending([OutboxEntry])
    /// Refused for good and dropped; the reason is for the user.
    case rejected(OutboxItem, reason: String)
}

/// Sends crew commands and reports in order, holding them while offline (D9).
///
/// Items go out strictly in the order they were made: a transient failure stops the flush, so
/// a later action never overtakes an earlier one. Rejected items are dropped and reported.
public actor Outbox {
    public enum FlushResult: Hashable, Sendable {
        /// Everything was sent or rejected.
        case empty
        /// A transient failure; the rest waits.
        case blocked
    }

    private let store: any OutboxStore
    private let sink: any CommandSink
    private let backoff: Backoff
    private let now: @Sendable () -> Date
    private let random: @Sendable () -> Double
    private let sleep: @Sendable (Duration) async throws -> Void
    private var entries: [OutboxEntry] = []
    private let broadcast = Broadcast<OutboxEvent>()
    /// Signals ``run()`` that there may be work while it waits on an empty queue.
    private let wakeUps: AsyncStream<Void>
    private let wake: AsyncStream<Void>.Continuation
    /// The backoff sleep after a failed flush; cancelling it retries at once.
    private var backoffWait: Task<Void, Never>?

    public init(
        store: any OutboxStore,
        sink: any CommandSink,
        backoff: Backoff = Backoff(base: .seconds(2), cap: .seconds(60)),
        now: @escaping @Sendable () -> Date = Date.init,
        random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.store = store
        self.sink = sink
        self.backoff = backoff
        self.now = now
        self.random = random
        self.sleep = sleep
        (wakeUps, wake) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    public var pending: [OutboxEntry] { entries }

    /// Commands still waiting, for showing optimistically.
    public var pendingCommands: [HotspotCommand] {
        entries.compactMap {
            guard case .command(let command) = $0.item else { return nil }
            return command
        }
    }

    /// The current queue now, then every change and rejection.
    public nonisolated func events() -> AsyncStream<OutboxEvent> {
        let (id, stream) = broadcast.subscribe()
        Task { await broadcast.yield(.pending(entries), to: id) }
        return stream
    }

    /// Loads entries saved by an earlier run, ahead of anything queued since.
    public func restore() async throws {
        entries = try await store.load() + entries
        await changed()
    }

    public func enqueue(_ item: OutboxItem) async {
        entries.append(OutboxEntry(item: item, enqueuedAt: now()))
        await changed()
        wake.yield()
    }

    /// Ends any backoff wait, for example when the connection comes back.
    public func retryNow() {
        backoffWait?.cancel()
        wake.yield()
    }

    /// Sends entries in order until the queue is empty or a transient failure blocks it.
    public func flush() async -> FlushResult {
        while let entry = entries.first {
            do throws(SubmissionError) {
                switch entry.item {
                case .command(let command): _ = try await sink.submit(command)
                case .report(let report): _ = try await sink.submit(report)
                }
                entries.removeFirst()
            } catch {
                switch error {
                case .rejected(let reason):
                    entries.removeFirst()
                    broadcast.yield(.rejected(entry.item, reason: reason))
                case .unavailable:
                    entries[0].attempts += 1
                    await changed()
                    return .blocked
                }
            }
            await changed()
        }
        return .empty
    }

    /// Flushes whenever there is work, backing off after failures, until cancelled.
    public func run() async {
        var wakeUps = self.wakeUps.makeAsyncIterator()
        while !Task.isCancelled {
            switch await flush() {
            case .empty:
                guard await wakeUps.next() != nil else { return }
            case .blocked:
                let attempts = entries.first?.attempts ?? 1
                let delay = backoff.delay(forAttempt: attempts - 1, unit: random())
                let wait = Task { [sleep] in _ = try? await sleep(delay) }
                backoffWait = wait
                await wait.value
                backoffWait = nil
            }
        }
    }

    private func changed() async {
        try? await store.save(entries)
        broadcast.yield(.pending(entries))
    }
}
