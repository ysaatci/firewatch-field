import Foundation

/// Something that happened at the fire. Every data source (the simulator, the server,
/// and later the real drone pipeline) speaks this vocabulary.
public enum FeedEvent: Hashable, Sendable {
    case hotspotObserved(HotspotObservation)
    case hotspotCommandApplied(HotspotCommand)
    case perimeterUpdated(FirePerimeter)
    case droneMoved(DroneUpdate)

    public var time: Date {
        switch self {
        case .hotspotObserved(let observation): observation.reading.time
        case .hotspotCommandApplied(let command): command.issuedAt
        case .perimeterUpdated(let perimeter): perimeter.time
        case .droneMoved(let update): update.position.time
        }
    }
}

/// A drone's thermal measurement of a hotspot.
public struct HotspotObservation: Hashable, Sendable {
    public var hotspotID: Hotspot.ID
    public var coordinate: Coordinate
    public var reading: TemperatureReading
    /// Detection confidence in `0...1`.
    public var confidence: Double
    public var droneID: Drone.ID

    public init(
        hotspotID: Hotspot.ID,
        coordinate: Coordinate,
        reading: TemperatureReading,
        confidence: Double,
        droneID: Drone.ID
    ) {
        self.hotspotID = hotspotID
        self.coordinate = coordinate
        self.reading = reading
        self.confidence = confidence
        self.droneID = droneID
    }
}

/// A crew member's workflow action on a hotspot.
public struct HotspotCommand: Identifiable, Hashable, Sendable {
    public typealias ID = Identifier<HotspotCommand>

    /// Generated on the device; the server uses it to ignore retried duplicates.
    public let id: ID
    public var hotspotID: Hotspot.ID
    public var action: HotspotAction
    public var issuedAt: Date

    public init(id: ID = .unique(), hotspotID: Hotspot.ID, action: HotspotAction, issuedAt: Date) {
        self.id = id
        self.hotspotID = hotspotID
        self.action = action
        self.issuedAt = issuedAt
    }
}

/// A drone's latest position.
public struct DroneUpdate: Hashable, Sendable {
    public var droneID: Drone.ID
    public var name: String
    public var position: DronePosition

    public init(droneID: Drone.ID, name: String, position: DronePosition) {
        self.droneID = droneID
        self.name = name
        self.position = position
    }
}
