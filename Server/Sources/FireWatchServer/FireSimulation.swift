import FireWatchAPI
import FireWatchCore
import FireWatchSimulator
import Foundation

/// The server's replay: a ``ReplaySession`` behind an actor, so requests and the ticker
/// never see half-applied state. Adds the time source, scenario caching and wire types.
actor FireSimulation {
    private let now: @Sendable () -> Date
    private var scenarios: [ScenarioPreset: Scenario] = [:]
    private var session: ReplaySession

    init(preset: ScenarioPreset, speed: Double, startMinute: Double, now: @escaping @Sendable () -> Date) {
        self.now = now
        let scenario = Scenario(preset.configuration)
        scenarios[preset] = scenario
        session = ReplaySession(
            scenario: scenario, preset: preset, speed: speed, startMinute: startMinute, now: now())
    }

    var state: FireState { session.state }
    var reports: [SightingReport.ID: SightingReport] { session.reports }
    var scenarioNow: Date { session.scenarioNow }

    /// The state and the scenario time it is valid for, read together.
    func current() -> (state: FireState, time: Date) {
        (session.state, session.scenarioNow)
    }

    /// Applies and returns the events since the previous call, in time order.
    func advance() -> [FeedEvent] {
        session.advance(to: now())
    }

    func status() -> ReplayStatusDTO {
        ReplayStatusDTO(session.status(at: now()))
    }

    /// Starts, pauses or resets the replay. Nothing changes unless the whole request is valid.
    /// - Returns: The new status, and whether the scenario restarted, in which case clients must resync.
    /// - Throws: ``APIFailure`` for a speed out of range or an unknown preset.
    func control(_ request: ReplayControlDTO) throws(APIFailure) -> (status: ReplayStatusDTO, restarted: Bool) {
        if let speed = request.speed, !ReplayControlDTO.speedRange.contains(speed) {
            throw .invalidPayload("speed must be within \(ReplayControlDTO.speedRange)")
        }
        var preset = session.preset
        if let name = request.preset {
            guard let named = ScenarioPreset(rawValue: name) else { throw .invalidPayload("unknown preset \(name)") }
            preset = named
        }

        let current = now()
        if let speed = request.speed { session.setSpeed(speed, at: current) }
        switch request.action {
        case .start:
            session.start(at: current)
        case .pause:
            session.pause(at: current)
        case .reset:
            let scenario = scenarios[preset] ?? Scenario(preset.configuration)
            scenarios[preset] = scenario
            session.reset(to: scenario, preset: preset, at: current)
            return (status(), true)
        }
        return (status(), false)
    }

    /// See ``ReplaySession/execute(_:)``.
    func execute(_ command: HotspotCommand) throws(CommandRejection) -> (
        outcome: SubmissionOutcome, event: FeedEvent?
    ) {
        try session.execute(command)
    }

    func submit(_ report: SightingReport) -> SubmissionOutcome {
        session.submit(report)
    }
}

extension ReplayStatusDTO {
    init(_ status: ReplayStatus) {
        self.init(
            preset: status.preset.rawValue,
            state: State(rawValue: status.phase.rawValue) ?? .running,
            speed: status.speed,
            scenarioMinute: status.scenarioMinute,
            scenarioMinutes: status.scenarioMinutes
        )
    }
}
