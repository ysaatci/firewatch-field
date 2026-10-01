import Foundation
import TestSupport
import Testing

@testable import FireWatchCore

/// A sink that answers from a script and records what was sent.
actor ScriptedSink: CommandSink {
    private var answers: [Result<SubmissionOutcome, SubmissionError>]
    private(set) var sent: [String] = []

    init(_ answers: [Result<SubmissionOutcome, SubmissionError>] = []) {
        self.answers = answers
    }

    func script(_ answers: [Result<SubmissionOutcome, SubmissionError>]) {
        self.answers += answers
    }

    private func answer(_ id: String) throws(SubmissionError) -> SubmissionOutcome {
        sent.append(id)
        return try (answers.isEmpty ? .success(.applied) : answers.removeFirst()).get()
    }

    func submit(_ command: HotspotCommand) throws(SubmissionError) -> SubmissionOutcome {
        try answer(command.id.rawValue)
    }

    func submit(_ report: SightingReport) throws(SubmissionError) -> SubmissionOutcome {
        try answer(report.id.rawValue)
    }
}

struct OutboxTests {
    let store = InMemoryOutboxStore()

    func command(_ id: String, _ action: HotspotAction = .assign) -> OutboxItem {
        .command(HotspotCommand(id: HotspotCommand.ID(id), hotspotID: "hs-1", action: action, issuedAt: .now))
    }

    func report(_ id: String) -> OutboxItem {
        .report(
            SightingReport(id: SightingReport.ID(id), createdAt: .now, coordinate: .manavgat, severity: .low, note: ""))
    }

    @Test func sendsEverythingInOrder() async {
        let sink = ScriptedSink()
        let outbox = Outbox(store: store, sink: sink)
        await outbox.enqueue(command("c-1"))
        await outbox.enqueue(report("r-1"))
        await outbox.enqueue(command("c-2"))
        #expect(await outbox.flush() == .empty)
        #expect(await sink.sent == ["c-1", "r-1", "c-2"])
        #expect(await outbox.pending.isEmpty)
        #expect(await store.load().isEmpty)
    }

    @Test func transientFailureStopsTheFlushAndKeepsOrder() async {
        let sink = ScriptedSink([.success(.applied), .failure(.unavailable)])
        let outbox = Outbox(store: store, sink: sink)
        for id in ["c-1", "c-2", "c-3"] { await outbox.enqueue(command(id)) }
        #expect(await outbox.flush() == .blocked)
        #expect(await sink.sent == ["c-1", "c-2"])
        #expect(await outbox.pending.map(\.item.id) == ["c-2", "c-3"])
        #expect(await outbox.pending.first?.attempts == 1)

        #expect(await outbox.flush() == .empty)
        #expect(await sink.sent == ["c-1", "c-2", "c-2", "c-3"])
    }

    @Test func rejectedItemsAreDroppedAndReported() async {
        let sink = ScriptedSink([.failure(.rejected("verifyCold is not allowed from flaredUp"))])
        let outbox = Outbox(store: store, sink: sink)
        var events = outbox.events().makeAsyncIterator()
        _ = await events.next()  // the initial, empty queue
        await outbox.enqueue(command("c-1", .verifyCold))
        await outbox.enqueue(command("c-2"))
        #expect(await outbox.flush() == .empty)
        #expect(await sink.sent == ["c-1", "c-2"])

        var rejection: OutboxEvent?
        while let event = await events.next() {
            if case .rejected = event {
                rejection = event
                break
            }
        }
        guard case .rejected(let item, let reason)? = rejection else {
            Issue.record("expected a rejection")
            return
        }
        #expect(item.id == "c-1")
        #expect(reason == "verifyCold is not allowed from flaredUp")
    }

    @Test func queueSurvivesARestart() async throws {
        let firstRun = Outbox(store: store, sink: ScriptedSink([.failure(.unavailable)]))
        await firstRun.enqueue(command("c-1"))
        await firstRun.enqueue(report("r-1"))
        _ = await firstRun.flush()

        let sink = ScriptedSink()
        let secondRun = Outbox(store: store, sink: sink)  // the app was killed and relaunched
        try await secondRun.restore()
        #expect(await secondRun.pending.map(\.item.id) == ["c-1", "r-1"])
        #expect(await secondRun.pending.first?.attempts == 1)
        _ = await secondRun.flush()
        #expect(await sink.sent == ["c-1", "r-1"])
    }

    @Test func pendingCommandsExcludeReports() async {
        let outbox = Outbox(store: store, sink: ScriptedSink())
        await outbox.enqueue(command("c-1"))
        await outbox.enqueue(report("r-1"))
        #expect(await outbox.pendingCommands.map(\.id.rawValue) == ["c-1"])
    }

    @Test func runRetriesAfterBackoffAndOnRetryNow() async throws {
        let sink = ScriptedSink([.failure(.unavailable), .failure(.unavailable)])
        let sleeper = ManualSleeper()
        let outbox = Outbox(store: store, sink: sink, random: { 0.5 }, sleep: { try await sleeper.sleep($0) })
        let running = Task { await outbox.run() }
        await outbox.enqueue(command("c-1"))

        try await eventually { await (sink.sent.count, sleeper.waiting) == (1, 1) }
        await sleeper.release()  // the backoff ends
        try await eventually { await (sink.sent.count, sleeper.waiting) == (2, 1) }
        await outbox.retryNow()  // the connection is back: don't wait out the backoff
        try await eventually { await outbox.pending.isEmpty }
        #expect(await sink.sent == ["c-1", "c-1", "c-1"])
        running.cancel()
    }
}

/// Polls `condition` until it holds, failing the test after `timeout`.
func eventually(timeout: Duration = .seconds(5), _ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !(await condition()) {
        guard ContinuousClock.now < deadline else {
            Issue.record("Condition not met within \(timeout)")
            return
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}
