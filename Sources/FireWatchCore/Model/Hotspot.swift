import Foundation

/// A spot a drone's thermal camera has measured as hot.
public struct Hotspot: Identifiable, Hashable, Sendable {
    public typealias ID = Identifier<Hotspot>

    /// Readings kept for the trend sparkline; older ones are dropped.
    public static let historyLimit = 48

    public let id: ID
    public var coordinate: Coordinate
    /// Detection confidence in `0...1`.
    public var confidence: Double
    public let firstSeen: Date
    public var workflow: HotspotWorkflow
    private var history: TimeOrderedLog<TemperatureReading>

    public init(
        id: ID,
        coordinate: Coordinate,
        confidence: Double,
        reading: TemperatureReading,
        workflow: HotspotWorkflow = .initial
    ) {
        self.id = id
        self.coordinate = coordinate
        self.confidence = confidence
        self.firstSeen = reading.time
        self.workflow = workflow
        self.history = TimeOrderedLog(first: reading, limit: Self.historyLimit)
    }

    /// Restores a stored hotspot, or `nil` without readings. `firstSeen` may predate the
    /// oldest reading, which can have been trimmed from the history.
    public init?(
        id: ID,
        coordinate: Coordinate,
        confidence: Double,
        firstSeen: Date,
        readings: [TemperatureReading],
        workflow: HotspotWorkflow
    ) {
        guard let first = readings.first else { return nil }
        self.id = id
        self.coordinate = coordinate
        self.confidence = confidence
        self.firstSeen = min(firstSeen, first.time)
        self.workflow = workflow
        self.history = TimeOrderedLog(first: first, limit: Self.historyLimit)
        for reading in readings.dropFirst() { history.append(reading) }
    }

    public var status: HotspotStatus { workflow.status }
    /// Recent readings, oldest first.
    public var readings: [TemperatureReading] { history.samples }
    public var temperatureCelsius: Double { history.latest.celsius }
    public var lastSeen: Date { history.latest.time }
    public var severity: Severity { Severity(celsius: temperatureCelsius) }

    /// Adds a reading newer than the latest; older or repeated readings are ignored.
    /// - Returns: Whether the reading was recorded.
    @discardableResult
    public mutating func record(_ reading: TemperatureReading, confidence: Double) -> Bool {
        guard history.append(reading) else { return false }
        self.confidence = confidence
        return true
    }
}

/// A surface temperature measured at a point in time.
public struct TemperatureReading: Timestamped, Hashable, Sendable {
    public var time: Date
    public var celsius: Double

    public init(time: Date, celsius: Double) {
        self.time = time
        self.celsius = celsius
    }
}

/// How dangerous a hotspot is, from its surface temperature.
public enum Severity: Int, CaseIterable, Comparable, Sendable {
    case low, moderate, high, extreme

    /// Lower bound, in °C, of each severity above `low`.
    public static let thresholds: [(Severity, Double)] = [(.extreme, 400), (.high, 200), (.moderate, 80)]

    public init(celsius: Double) {
        self = Self.thresholds.first { celsius >= $0.1 }?.0 ?? .low
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
