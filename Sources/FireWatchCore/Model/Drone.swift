import Foundation

/// A survey drone and where it has recently been.
public struct Drone: Identifiable, Hashable, Sendable {
    public typealias ID = Identifier<Drone>

    /// Positions kept for the recent-track polyline.
    public static let trackLimit = 30

    public let id: ID
    public var name: String
    private var log: TimeOrderedLog<DronePosition>

    public init(id: ID, name: String, position: DronePosition) {
        self.id = id
        self.name = name
        self.log = TimeOrderedLog(first: position, limit: Self.trackLimit)
    }

    public var position: DronePosition { log.latest }
    /// Recent positions, oldest first.
    public var track: [DronePosition] { log.samples }

    /// Records a newer position. Older positions are ignored.
    public mutating func move(to position: DronePosition) {
        log.append(position)
    }
}

/// A drone's state at a point in time.
public struct DronePosition: Timestamped, Hashable, Sendable {
    public var time: Date
    public var coordinate: Coordinate
    /// Degrees clockwise from true north.
    public var headingDegrees: Double
    public var altitudeMetres: Double
    /// Remaining battery in `0...1`.
    public var battery: Double

    public init(
        time: Date, coordinate: Coordinate, headingDegrees: Double, altitudeMetres: Double, battery: Double
    ) {
        self.time = time
        self.coordinate = coordinate
        self.headingDegrees = headingDegrees
        self.altitudeMetres = altitudeMetres
        self.battery = battery
    }
}
