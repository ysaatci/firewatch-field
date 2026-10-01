import Foundation

// Wire formats. Enumerations travel as strings and are validated by the mappers, so Core
// stays free of Codable and an unknown value fails one field rather than silently mapping.

/// `GET /v1/snapshot`: everything known right now.
public struct SnapshotDTO: Hashable, Sendable, Codable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var hotspots: [HotspotDTO]
    public var drones: [DroneDTO]
    public var perimeter: PerimeterDTO?

    public init(
        schemaVersion: Int = API.schemaVersion,
        generatedAt: Date,
        hotspots: [HotspotDTO],
        drones: [DroneDTO],
        perimeter: PerimeterDTO?
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.hotspots = hotspots
        self.drones = drones
        self.perimeter = perimeter
    }
}

public struct HotspotDTO: Hashable, Sendable, Codable {
    public var id: String
    public var location: Position
    public var confidence: Double
    public var firstSeen: Date
    /// One of `new`, `assigned`, `extinguished`, `verifiedCold`, `flaredUp`.
    public var status: String
    public var flareUps: Int
    /// Oldest first.
    public var readings: [ReadingDTO]

    public init(
        id: String,
        location: Position,
        confidence: Double,
        firstSeen: Date,
        status: String,
        flareUps: Int,
        readings: [ReadingDTO]
    ) {
        self.id = id
        self.location = location
        self.confidence = confidence
        self.firstSeen = firstSeen
        self.status = status
        self.flareUps = flareUps
        self.readings = readings
    }
}

public struct ReadingDTO: Hashable, Sendable, Codable {
    public var time: Date
    public var celsius: Double

    public init(time: Date, celsius: Double) {
        self.time = time
        self.celsius = celsius
    }
}

public struct DroneDTO: Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    /// Oldest first; the last entry is the current position.
    public var track: [DronePositionDTO]

    public init(id: String, name: String, track: [DronePositionDTO]) {
        self.id = id
        self.name = name
        self.track = track
    }
}

public struct DronePositionDTO: Hashable, Sendable, Codable {
    public var time: Date
    public var location: Position
    public var headingDegrees: Double
    public var altitudeMetres: Double
    public var battery: Double

    public init(time: Date, location: Position, headingDegrees: Double, altitudeMetres: Double, battery: Double) {
        self.time = time
        self.location = location
        self.headingDegrees = headingDegrees
        self.altitudeMetres = altitudeMetres
        self.battery = battery
    }
}

/// A fire perimeter as a GeoJSON feature with `MultiPolygon` geometry.
public typealias PerimeterDTO = Feature<PerimeterProperties>

public struct PerimeterProperties: Hashable, Sendable, Codable {
    public var time: Date
    public var areaHectares: Double

    public init(time: Date, areaHectares: Double) {
        self.time = time
        self.areaHectares = areaHectares
    }
}

/// `GET /v1/perimeters`: the perimeter history, oldest first, openable in any GIS tool.
public typealias PerimeterHistoryDTO = FeatureCollection<PerimeterProperties>

public struct ObservationDTO: Hashable, Sendable, Codable {
    public var hotspotID: String
    public var location: Position
    public var time: Date
    public var celsius: Double
    public var confidence: Double
    public var droneID: String

    public init(
        hotspotID: String,
        location: Position,
        time: Date,
        celsius: Double,
        confidence: Double,
        droneID: String
    ) {
        self.hotspotID = hotspotID
        self.location = location
        self.time = time
        self.celsius = celsius
        self.confidence = confidence
        self.droneID = droneID
    }
}

/// `POST /v1/commands`: a crew workflow action. Retrying with the same `id` is safe.
public struct CommandDTO: Hashable, Sendable, Codable {
    public var id: String
    public var hotspotID: String
    /// One of `assign`, `unassign`, `extinguish`, `verifyCold`, `flareUp`.
    public var action: String
    public var issuedAt: Date

    public init(id: String, hotspotID: String, action: String, issuedAt: Date) {
        self.id = id
        self.hotspotID = hotspotID
        self.action = action
        self.issuedAt = issuedAt
    }
}

/// The server's answer to a command it accepted.
public struct CommandReceiptDTO: Hashable, Sendable, Codable {
    public enum Outcome: String, Hashable, Sendable, Codable {
        /// Applied now.
        case applied
        /// Already applied earlier; this was a retry.
        case duplicate
    }

    public var commandID: String
    public var outcome: Outcome

    public init(commandID: String, outcome: Outcome) {
        self.commandID = commandID
        self.outcome = outcome
    }
}

public struct DroneUpdateDTO: Hashable, Sendable, Codable {
    public var droneID: String
    public var name: String
    public var position: DronePositionDTO

    public init(droneID: String, name: String, position: DronePositionDTO) {
        self.droneID = droneID
        self.name = name
        self.position = position
    }
}

/// One event, encoded as `{"type": "<case>", "data": {...}}`.
public enum EventDTO: Hashable, Sendable, Codable {
    case hotspotObserved(ObservationDTO)
    case hotspotCommandApplied(CommandDTO)
    case perimeterUpdated(PerimeterDTO)
    case droneMoved(DroneUpdateDTO)
    /// A type this client doesn't know, from a newer server. Skipped rather than failing the batch.
    case unknown(type: String)

    private enum CodingKeys: String, CodingKey {
        case type, data
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "hotspotObserved": self = .hotspotObserved(try container.decode(ObservationDTO.self, forKey: .data))
        case "hotspotCommandApplied":
            self = .hotspotCommandApplied(try container.decode(CommandDTO.self, forKey: .data))
        case "perimeterUpdated": self = .perimeterUpdated(try container.decode(PerimeterDTO.self, forKey: .data))
        case "droneMoved": self = .droneMoved(try container.decode(DroneUpdateDTO.self, forKey: .data))
        default: self = .unknown(type: type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hotspotObserved(let data):
            try container.encode("hotspotObserved", forKey: .type)
            try container.encode(data, forKey: .data)
        case .hotspotCommandApplied(let data):
            try container.encode("hotspotCommandApplied", forKey: .type)
            try container.encode(data, forKey: .data)
        case .perimeterUpdated(let data):
            try container.encode("perimeterUpdated", forKey: .type)
            try container.encode(data, forKey: .data)
        case .droneMoved(let data):
            try container.encode("droneMoved", forKey: .type)
            try container.encode(data, forKey: .data)
        case .unknown(let type):
            try container.encode(type, forKey: .type)
        }
    }
}

/// A WebSocket message on `/v1/stream`: the events since the previous message, in time order.
public struct EventBatchDTO: Hashable, Sendable, Codable {
    public var schemaVersion: Int
    public var events: [EventDTO]

    public init(schemaVersion: Int = API.schemaVersion, events: [EventDTO]) {
        self.schemaVersion = schemaVersion
        self.events = events
    }
}

/// `POST /v1/reports`: a ground sighting. Retrying with the same `id` is safe.
public struct ReportDTO: Hashable, Sendable, Codable {
    public var id: String
    public var createdAt: Date
    public var location: Position
    /// One of `low`, `moderate`, `high`, `extreme`.
    public var severity: String
    public var note: String
    /// JPEG bytes, base64-encoded in JSON.
    public var photoJPEG: Data?

    public init(id: String, createdAt: Date, location: Position, severity: String, note: String, photoJPEG: Data?) {
        self.id = id
        self.createdAt = createdAt
        self.location = location
        self.severity = severity
        self.note = note
        self.photoJPEG = photoJPEG
    }
}

/// The body of every 4xx/5xx response.
public struct ErrorDTO: Hashable, Sendable, Codable {
    /// Machine-readable, for example `unknownHotspot` or `notAllowed`.
    public var code: String
    /// Human-readable, for logs.
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}
