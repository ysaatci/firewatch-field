// Simulator-only payloads: replay control and fault injection (FR-S3, FR-S5).

/// `GET /v1/control`: where the replay is.
public struct ReplayStatusDTO: Hashable, Sendable, Codable {
    public enum State: String, Hashable, Sendable, Codable {
        case running, paused, finished
    }

    public var preset: String
    public var state: State
    /// Scenario seconds per real second.
    public var speed: Double
    public var scenarioMinute: Double
    /// Length of the scenario, in minutes.
    public var scenarioMinutes: Int

    public init(preset: String, state: State, speed: Double, scenarioMinute: Double, scenarioMinutes: Int) {
        self.preset = preset
        self.state = state
        self.speed = speed
        self.scenarioMinute = scenarioMinute
        self.scenarioMinutes = scenarioMinutes
    }
}

/// `POST /v1/control`: start, pause or reset the replay, optionally changing speed or preset.
public struct ReplayControlDTO: Hashable, Sendable, Codable {
    public enum Action: String, Hashable, Sendable, Codable {
        case start, pause, reset
    }

    public static let speedRange: ClosedRange<Double> = 1...600

    public var action: Action
    /// Scenario seconds per real second, within ``speedRange``.
    public var speed: Double?
    /// Only used with `reset`.
    public var preset: String?

    public init(action: Action, speed: Double? = nil, preset: String? = nil) {
        self.action = action
        self.speed = speed
        self.preset = preset
    }
}

/// `POST /v1/control/faults`: make the server slow or unreliable on purpose.
public struct FaultsDTO: Hashable, Sendable, Codable {
    public static let none = FaultsDTO(latencyMilliseconds: 0, dropRate: 0)

    /// Added to every `/v1` request.
    public var latencyMilliseconds: Int
    /// Fraction of `/v1` requests, in `0...1`, answered with `503 injectedFault`.
    public var dropRate: Double

    public init(latencyMilliseconds: Int, dropRate: Double) {
        self.latencyMilliseconds = latencyMilliseconds
        self.dropRate = dropRate
    }
}
