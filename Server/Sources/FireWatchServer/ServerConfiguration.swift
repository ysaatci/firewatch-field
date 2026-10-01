import FireWatchAPI
import FireWatchSimulator
import Foundation
import Vapor

/// Everything the server needs to start, normally read from the environment.
public struct ServerConfiguration: Sendable {
    /// Bearer token every `/v1` request must carry.
    public var token: String
    public var preset: ScenarioPreset
    /// Scenario seconds per real second.
    public var speed: Double
    /// Scenario minute to start at, so there is something to see straight away.
    public var startMinute: Double
    /// How often scenario events are pushed to clients; `nil` disables the ticker (tests drive time by hand).
    public var tickInterval: Duration?
    /// The current time; injectable so tests control it.
    public var now: @Sendable () -> Date

    public init(
        token: String,
        preset: ScenarioPreset = .default,
        speed: Double = 30,
        startMinute: Double = 60,
        tickInterval: Duration? = .seconds(1),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.token = token
        self.preset = preset
        self.speed = speed
        self.startMinute = startMinute
        self.tickInterval = tickInterval
        self.now = now
    }

    /// Reads `FIREWATCH_TOKEN` (required), `FIREWATCH_PRESET`, `FIREWATCH_SPEED` and `FIREWATCH_START_MINUTE`.
    public static func fromEnvironment() throws -> ServerConfiguration {
        guard let token = Environment.get("FIREWATCH_TOKEN"), !token.isEmpty else {
            throw ConfigurationError("FIREWATCH_TOKEN must be set")
        }
        var configuration = ServerConfiguration(token: token)
        if let name = Environment.get("FIREWATCH_PRESET") {
            guard let preset = ScenarioPreset(rawValue: name) else {
                throw ConfigurationError("FIREWATCH_PRESET must be one of \(ScenarioPreset.allCases.map(\.rawValue))")
            }
            configuration.preset = preset
        }
        if let text = Environment.get("FIREWATCH_SPEED") {
            guard let speed = Double(text), ReplayControlDTO.speedRange.contains(speed) else {
                throw ConfigurationError("FIREWATCH_SPEED must be a number from 1 to 600")
            }
            configuration.speed = speed
        }
        if let text = Environment.get("FIREWATCH_START_MINUTE") {
            guard let minute = Double(text), minute >= 0 else {
                throw ConfigurationError("FIREWATCH_START_MINUTE must be a non-negative number")
            }
            configuration.startMinute = minute
        }
        return configuration
    }
}

struct ConfigurationError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
