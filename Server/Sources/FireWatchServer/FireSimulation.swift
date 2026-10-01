import FireWatchAPI
import FireWatchCore
import FireWatchSimulator
import Foundation

/// The running simulation: one scenario playing on a replay clock, and everything that has
/// happened in it so far. An actor, so requests and the ticker never see half-applied state.
actor FireSimulation {
    private let now: @Sendable () -> Date
    private let startMinute: Double
    private var scenarios: [ScenarioPreset: Scenario] = [:]
    private(set) var preset: ScenarioPreset
    private var world: SimulatedWorld
    private var clock: ReplayClock
    private(set) var state: FireState
    /// Events before this scenario minute have been applied and handed out.
    private var emittedMinute: Double

    init(preset: ScenarioPreset, speed: Double, startMinute: Double, now: @escaping @Sendable () -> Date) {
        self.now = now
        self.startMinute = startMinute
        self.preset = preset
        let scenario = Scenario(preset.configuration)
        scenarios[preset] = scenario
        (world, clock, state, emittedMinute) = Self.begin(scenario, atMinute: startMinute, speed: speed, now: now())
    }

    /// A fresh run of `scenario` whose scenario time matches the wall clock at `startMinute`,
    /// with everything before `startMinute` already applied.
    private static func begin(_ scenario: Scenario, atMinute startMinute: Double, speed: Double, now: Date)
        -> (SimulatedWorld, ReplayClock, FireState, Double)
    {
        let endMinute = Double(scenario.configuration.minutes)
        let minute = min(startMinute, endMinute)
        let start = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down) - minute * 60)
        let world = SimulatedWorld(scenario: scenario, start: start)
        let clock = ReplayClock(startMinute: minute, endMinute: endMinute, speed: speed, now: now)
        return (world, clock, FireState(events: world.events(fromMinute: 0, toMinute: minute)), minute)
    }

    /// Scenario time up to which events have been applied.
    var scenarioNow: Date { world.date(atMinute: emittedMinute) }

    /// Applies and returns the events since the previous call, in time order.
    func advance() -> [FeedEvent] {
        let minute = clock.minute(at: now())
        guard minute > emittedMinute else { return [] }
        let events = world.events(fromMinute: emittedMinute, toMinute: minute)
        for event in events { state.apply(event) }
        emittedMinute = minute
        return events
    }

    func status() -> ReplayStatusDTO {
        let current = now()
        let state: ReplayStatusDTO.State =
            clock.isFinished(at: current) ? .finished : clock.isRunning ? .running : .paused
        return ReplayStatusDTO(
            preset: preset.rawValue,
            state: state,
            speed: clock.speed,
            scenarioMinute: clock.minute(at: current),
            scenarioMinutes: world.scenario.configuration.minutes
        )
    }

    /// Starts, pauses or resets the replay.
    /// - Returns: The new status, and whether the scenario restarted, in which case clients must resync.
    /// - Throws: ``APIFailure`` for a speed out of range or an unknown preset.
    func control(_ request: ReplayControlDTO) throws(APIFailure) -> (status: ReplayStatusDTO, restarted: Bool) {
        let current = now()
        if let speed = request.speed {
            guard ReplayControlDTO.speedRange.contains(speed) else {
                throw .invalidPayload("speed must be within \(ReplayControlDTO.speedRange)")
            }
            clock.setSpeed(speed, at: current)
        }
        switch request.action {
        case .start:
            clock.start(at: current)
        case .pause:
            clock.pause(at: current)
        case .reset:
            if let name = request.preset {
                guard let preset = ScenarioPreset(rawValue: name) else {
                    throw .invalidPayload("unknown preset \(name)")
                }
                self.preset = preset
            }
            let scenario = scenarios[preset] ?? Scenario(preset.configuration)
            scenarios[preset] = scenario
            (world, clock, state, emittedMinute) = Self.begin(
                scenario, atMinute: startMinute, speed: clock.speed, now: current)
            return (status(), true)
        }
        return (status(), false)
    }
}
