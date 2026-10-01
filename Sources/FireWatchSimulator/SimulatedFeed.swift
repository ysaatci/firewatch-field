import FireWatchCore
import Foundation

/// Demo mode: the simulator running on the device, as both the feed and the command sink (D7).
///
/// Behaves like the server: commands are validated and stamped with scenario time, and
/// extinguished hotspots cool. Building the scenario takes a moment, so create this off the
/// main thread.
public actor SimulatedFeed: DetectionFeed, CommandSink {
    private var session: ReplaySession
    private let now: @Sendable () -> Date
    private let tickInterval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private var subscribers: [UUID: AsyncStream<FeedUpdate>.Continuation] = [:]

    public init(
        preset: ScenarioPreset = .default,
        speed: Double = 30,
        startMinute: Double = 60,
        tickInterval: Duration = .seconds(1),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.now = now
        self.tickInterval = tickInterval
        self.sleep = sleep
        session = ReplaySession(
            scenario: Scenario(preset.configuration), preset: preset, speed: speed, startMinute: startMinute,
            now: now())
    }

    public nonisolated func updates() -> AsyncStream<FeedUpdate> {
        let (stream, continuation) = AsyncStream.makeStream(of: FeedUpdate.self)
        let id = UUID()
        let ticking = Task { await self.run(id, continuation) }
        continuation.onTermination = { _ in
            ticking.cancel()
            Task { await self.unsubscribe(id) }
        }
        return stream
    }

    private func run(_ id: UUID, _ continuation: AsyncStream<FeedUpdate>.Continuation) async {
        subscribers[id] = continuation
        continuation.yield(.connection(.live))
        continuation.yield(.snapshot(session.state, asOf: session.scenarioNow))
        while !Task.isCancelled {
            do {
                try await sleep(tickInterval)
            } catch {
                return
            }
            tick()
        }
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    /// Advances the replay to now and shares what happened.
    func tick() {
        let events = session.advance(to: now())
        if !events.isEmpty { broadcast(.events(events)) }
    }

    private func broadcast(_ update: FeedUpdate) {
        for subscriber in subscribers.values { subscriber.yield(update) }
    }

    public func submit(_ command: HotspotCommand) throws(SubmissionError) -> SubmissionOutcome {
        do {
            let (outcome, event) = try session.execute(command)
            if let event { broadcast(.events([event])) }
            return outcome
        } catch {
            throw .rejected(error.description)
        }
    }

    public func submit(_ report: SightingReport) -> SubmissionOutcome {
        session.submit(report)
    }
}
