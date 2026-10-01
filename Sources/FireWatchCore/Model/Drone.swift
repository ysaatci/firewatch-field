import Foundation

/// A survey drone and where it has recently been.
public struct Drone: Identifiable, Hashable, Sendable {
    public typealias ID = Identifier<Drone>

    /// Positions kept for the recent-track polyline.
    public static let trackLimit = 30

    public let id: ID
    public var name: String
    /// Positions in time order, newest last. Never empty.
    public private(set) var track: [DronePosition]

    public init(id: ID, name: String, position: DronePosition) {
        self.id = id
        self.name = name
        self.track = [position]
    }

    public var position: DronePosition {
        // `track` is never empty: it starts with one element and is only trimmed to the limit.
        track[track.count - 1]
    }

    /// Records a newer position. Older positions are ignored.
    public mutating func move(to position: DronePosition) {
        guard position.time >= self.position.time else { return }
        track.append(position)
        if track.count > Self.trackLimit {
            track.removeFirst(track.count - Self.trackLimit)
        }
    }
}

/// A drone's state at a point in time.
public struct DronePosition: Hashable, Sendable {
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
