import FireWatchCore
import Foundation

/// A scenario replaying on a clock, with crews acting on it: the whole simulated world as
/// both the server and the app's demo mode run it.
///
/// A value type driven by explicit `now` dates; callers decide where time comes from.
public struct ReplaySession: Sendable {
    public private(set) var preset: ScenarioPreset
    public private(set) var world: SimulatedWorld
    public private(set) var clock: ReplayClock
    /// Everything that has happened up to ``scenarioNow``.
    public private(set) var state: FireState
    /// Events before this scenario minute have been applied and handed out.
    public private(set) var emittedMinute: Double
    public private(set) var reports: [SightingReport.ID: SightingReport] = [:]
    /// IDs of commands already applied, so retries are recognised.
    private var appliedCommands: Set<HotspotCommand.ID> = []
    private let startMinute: Double

    /// Starts `scenario` at `startMinute`, with everything before it already applied and
    /// scenario time lined up with `now`.
    public init(scenario: Scenario, preset: ScenarioPreset, speed: Double, startMinute: Double, now: Date) {
        let endMinute = Double(scenario.configuration.minutes)
        let minute = min(startMinute, endMinute)
        let start = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down) - minute * 60)
        self.preset = preset
        self.startMinute = startMinute
        world = SimulatedWorld(scenario: scenario, start: start)
        clock = ReplayClock(startMinute: minute, endMinute: endMinute, speed: speed, now: now)
        state = FireState(events: world.events(fromMinute: 0, toMinute: minute))
        emittedMinute = minute
    }

    /// Scenario time up to which events have been applied.
    public var scenarioNow: Date { world.date(atMinute: emittedMinute) }

    public func status(at now: Date) -> ReplayStatus {
        let phase: ReplayStatus.Phase =
            clock.isFinished(at: now) ? .finished : clock.isRunning ? .running : .paused
        return ReplayStatus(
            preset: preset,
            phase: phase,
            speed: clock.speed,
            scenarioMinute: clock.minute(at: now),
            scenarioMinutes: world.scenario.configuration.minutes
        )
    }

    // MARK: Time

    /// Applies and returns the events up to `now`, in time order. Each event is returned once.
    public mutating func advance(to now: Date) -> [FeedEvent] {
        let minute = clock.minute(at: now)
        guard minute > emittedMinute else { return [] }
        let events = world.events(fromMinute: emittedMinute, toMinute: minute)
        for event in events { state.apply(event) }
        emittedMinute = minute
        return events
    }

    public mutating func start(at now: Date) { clock.start(at: now) }
    public mutating func pause(at now: Date) { clock.pause(at: now) }
    public mutating func setSpeed(_ speed: Double, at now: Date) { clock.setSpeed(speed, at: now) }

    /// Starts over with `scenario` at the original start minute, forgetting crews' actions.
    public mutating func reset(to scenario: Scenario, preset: ScenarioPreset, at now: Date) {
        self = ReplaySession(
            scenario: scenario, preset: preset, speed: clock.speed, startMinute: startMinute, now: now)
    }

    // MARK: Crews

    /// Applies a crew command, stamped with the current scenario time: at replay speed the
    /// device's own clock means nothing to the scenario.
    /// - Returns: `.duplicate` for a retry of an applied command; otherwise `.applied` and the event to share.
    /// - Throws: ``CommandRejection`` when the hotspot is unknown or the action isn't allowed now.
    public mutating func execute(_ command: HotspotCommand) throws(CommandRejection) -> (
        outcome: SubmissionOutcome, event: FeedEvent?
    ) {
        guard !appliedCommands.contains(command.id) else { return (.duplicate, nil) }
        var stamped = command
        stamped.issuedAt = scenarioNow
        let event = try state.execute(stamped)
        world.intervene(stamped)
        appliedCommands.insert(command.id)
        return (.applied, event)
    }

    /// Stores a sighting report; a retry with the same ID is a duplicate.
    public mutating func submit(_ report: SightingReport) -> SubmissionOutcome {
        guard reports[report.id] == nil else { return .duplicate }
        reports[report.id] = report
        return .applied
    }
}

/// Where a replay is.
public struct ReplayStatus: Hashable, Sendable {
    public enum Phase: String, Hashable, Sendable {
        case running, paused, finished
    }

    public var preset: ScenarioPreset
    public var phase: Phase
    /// Scenario seconds per real second.
    public var speed: Double
    public var scenarioMinute: Double
    public var scenarioMinutes: Int
}
