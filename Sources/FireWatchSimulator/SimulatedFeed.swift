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
    private let broadcast = Broadcast<FeedUpdate>()
    /// One clock for everyone watching; runs only while someone is.
    private var ticking: Task<Void, Never>?

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
        let (id, stream) = broadcast.subscribe { Task { await self.stopTickingIfUnwatched() } }
        Task { await welcome(id) }
        return stream
    }

    /// Greets a new subscriber with the current state, and starts the clock if it is the first.
    private func welcome(_ id: UUID) {
        broadcast.yield(.connection(.live), to: id)
        broadcast.yield(.snapshot(session.state, asOf: session.scenarioNow), to: id)
        guard ticking == nil else { return }
        ticking = Task {
            while !Task.isCancelled {
                do {
                    try await sleep(tickInterval)
                } catch {
                    return
                }
                tick()
            }
        }
    }

    private func stopTickingIfUnwatched() {
        guard !broadcast.hasSubscribers else { return }
        ticking?.cancel()
        ticking = nil
    }

    /// Advances the replay to now and shares what happened.
    func tick() {
        let events = session.advance(to: now())
        if !events.isEmpty { broadcast.yield(.events(events)) }
    }

    public func submit(_ command: HotspotCommand) throws(SubmissionError) -> SubmissionOutcome {
        do {
            let (outcome, event) = try session.execute(command)
            if let event { broadcast.yield(.events([event])) }
            return outcome
        } catch {
            throw .rejected(error.description)
        }
    }

    public func submit(_ report: SightingReport) -> SubmissionOutcome {
        session.submit(report)
    }
}
