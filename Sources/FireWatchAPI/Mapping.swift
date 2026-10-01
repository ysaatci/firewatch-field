import FireWatchCore
import Foundation

// Conversions between domain types and DTOs. Encoding can't fail; decoding validates
// everything the domain relies on and throws `MappingError`.

/// Why a payload couldn't be turned into domain values.
public enum MappingError: Error, Hashable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unknownStatus(String)
    case unknownAction(String)
    case unknownSeverity(String)
    case unreachableWorkflow(status: String, flareUps: Int)
    case noReadings(hotspotID: String)
    case noTrack(droneID: String)
    case notAPerimeter
}

private func checkVersion(_ version: Int) throws(MappingError) {
    guard version == API.schemaVersion else { throw .unsupportedSchemaVersion(version) }
}

// MARK: Geometry

extension Position {
    public init(_ coordinate: Coordinate) {
        self.init(longitude: coordinate.longitude, latitude: coordinate.latitude)
    }

    public var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

extension PerimeterDTO {
    /// A `MultiPolygon` feature. GeoJSON rings are closed, so each repeats its first position.
    public init(_ perimeter: FirePerimeter) {
        let closed = { (ring: [Coordinate]) in (ring + ring.prefix(1)).map(Position.init) }
        self.init(
            geometry: .multiPolygon(perimeter.polygons.map { [closed($0.exterior)] + $0.holes.map(closed) }),
            properties: PerimeterProperties(time: perimeter.time, areaHectares: perimeter.areaSquareMetres / 10_000)
        )
    }
}

extension FirePerimeter {
    /// Accepts `Polygon` or `MultiPolygon` geometry.
    public init(_ dto: PerimeterDTO) throws(MappingError) {
        let polygons: [[[Position]]]
        switch dto.geometry {
        case .polygon(let rings): polygons = [rings]
        case .multiPolygon(let all): polygons = all
        case .point: throw .notAPerimeter
        }
        let open = { (ring: [Position]) -> [Coordinate] in
            let coordinates = ring.map(\.coordinate)
            return coordinates.count > 1 && coordinates.first == coordinates.last
                ? Array(coordinates.dropLast()) : coordinates
        }
        self.init(
            time: dto.properties.time,
            polygons: polygons.compactMap { rings in
                rings.first.map { Polygon(exterior: open($0), holes: rings.dropFirst().map(open)) }
            }
        )
    }
}

// MARK: Hotspots

extension HotspotDTO {
    public init(_ hotspot: Hotspot) {
        self.init(
            id: hotspot.id.rawValue,
            location: Position(hotspot.coordinate),
            confidence: hotspot.confidence,
            firstSeen: hotspot.firstSeen,
            status: hotspot.status.rawValue,
            flareUps: hotspot.workflow.flareUps,
            readings: hotspot.readings.map { ReadingDTO(time: $0.time, celsius: $0.celsius) }
        )
    }
}

extension Hotspot {
    public init(_ dto: HotspotDTO) throws(MappingError) {
        guard let status = HotspotStatus(rawValue: dto.status) else { throw .unknownStatus(dto.status) }
        guard let workflow = HotspotWorkflow(restoring: status, flareUps: dto.flareUps) else {
            throw .unreachableWorkflow(status: dto.status, flareUps: dto.flareUps)
        }
        guard
            let hotspot = Hotspot(
                id: ID(dto.id),
                coordinate: dto.location.coordinate,
                confidence: dto.confidence,
                firstSeen: dto.firstSeen,
                readings: dto.readings.map { TemperatureReading(time: $0.time, celsius: $0.celsius) },
                workflow: workflow
            )
        else { throw .noReadings(hotspotID: dto.id) }
        self = hotspot
    }
}

extension ObservationDTO {
    public init(_ observation: HotspotObservation) {
        self.init(
            hotspotID: observation.hotspotID.rawValue,
            location: Position(observation.coordinate),
            time: observation.reading.time,
            celsius: observation.reading.celsius,
            confidence: observation.confidence,
            droneID: observation.droneID.rawValue
        )
    }
}

extension HotspotObservation {
    public init(_ dto: ObservationDTO) {
        self.init(
            hotspotID: Hotspot.ID(dto.hotspotID),
            coordinate: dto.location.coordinate,
            reading: TemperatureReading(time: dto.time, celsius: dto.celsius),
            confidence: dto.confidence,
            droneID: Drone.ID(dto.droneID)
        )
    }
}

extension CommandDTO {
    public init(_ command: HotspotCommand) {
        self.init(
            id: command.id.rawValue,
            hotspotID: command.hotspotID.rawValue,
            action: command.action.rawValue,
            issuedAt: command.issuedAt
        )
    }
}

extension HotspotCommand {
    public init(_ dto: CommandDTO) throws(MappingError) {
        guard let action = HotspotAction(rawValue: dto.action) else { throw .unknownAction(dto.action) }
        self.init(id: ID(dto.id), hotspotID: Hotspot.ID(dto.hotspotID), action: action, issuedAt: dto.issuedAt)
    }
}

// MARK: Drones

extension DronePositionDTO {
    public init(_ position: DronePosition) {
        self.init(
            time: position.time,
            location: Position(position.coordinate),
            headingDegrees: position.headingDegrees,
            altitudeMetres: position.altitudeMetres,
            battery: position.battery
        )
    }
}

extension DronePosition {
    public init(_ dto: DronePositionDTO) {
        self.init(
            time: dto.time,
            coordinate: dto.location.coordinate,
            headingDegrees: dto.headingDegrees,
            altitudeMetres: dto.altitudeMetres,
            battery: dto.battery
        )
    }
}

extension DroneDTO {
    public init(_ drone: Drone) {
        self.init(id: drone.id.rawValue, name: drone.name, track: drone.track.map(DronePositionDTO.init))
    }
}

extension Drone {
    public init(_ dto: DroneDTO) throws(MappingError) {
        guard let first = dto.track.first else { throw .noTrack(droneID: dto.id) }
        self.init(id: ID(dto.id), name: dto.name, position: DronePosition(first))
        for position in dto.track.dropFirst() { move(to: DronePosition(position)) }
    }
}

extension DroneUpdateDTO {
    public init(_ update: DroneUpdate) {
        self.init(droneID: update.droneID.rawValue, name: update.name, position: DronePositionDTO(update.position))
    }
}

extension DroneUpdate {
    public init(_ dto: DroneUpdateDTO) {
        self.init(droneID: Drone.ID(dto.droneID), name: dto.name, position: DronePosition(dto.position))
    }
}

// MARK: Reports

extension Severity {
    /// The wire name: `low`, `moderate`, `high` or `extreme`.
    public var name: String { String(describing: self) }

    public init(name: String) throws(MappingError) {
        guard let severity = Severity.allCases.first(where: { $0.name == name }) else { throw .unknownSeverity(name) }
        self = severity
    }
}

extension ReportDTO {
    public init(_ report: SightingReport, photoJPEG: Data?) {
        self.init(
            id: report.id.rawValue,
            createdAt: report.createdAt,
            location: Position(report.coordinate),
            severity: report.severity.name,
            note: report.note,
            photoJPEG: photoJPEG
        )
    }
}

extension SightingReport {
    /// The photo bytes stay in the DTO; storing them is up to the receiver.
    public init(_ dto: ReportDTO) throws(MappingError) {
        self.init(
            id: ID(dto.id),
            createdAt: dto.createdAt,
            coordinate: dto.location.coordinate,
            severity: try Severity(name: dto.severity),
            note: dto.note
        )
    }
}

// MARK: Events and snapshots

extension EventDTO {
    public init(_ event: FeedEvent) {
        switch event {
        case .hotspotObserved(let observation): self = .hotspotObserved(ObservationDTO(observation))
        case .hotspotCommandApplied(let command): self = .hotspotCommandApplied(CommandDTO(command))
        case .perimeterUpdated(let perimeter): self = .perimeterUpdated(PerimeterDTO(perimeter))
        case .droneMoved(let update): self = .droneMoved(DroneUpdateDTO(update))
        }
    }
}

extension FeedEvent {
    /// The domain event, or `nil` for an event type this client doesn't know.
    public init?(_ dto: EventDTO) throws(MappingError) {
        switch dto {
        case .hotspotObserved(let observation): self = .hotspotObserved(HotspotObservation(observation))
        case .hotspotCommandApplied(let command): self = .hotspotCommandApplied(try HotspotCommand(command))
        case .perimeterUpdated(let perimeter): self = .perimeterUpdated(try FirePerimeter(perimeter))
        case .droneMoved(let update): self = .droneMoved(DroneUpdate(update))
        case .unknown: return nil
        }
    }
}

extension EventBatchDTO {
    public init(_ events: [FeedEvent]) {
        self.init(events: events.map(EventDTO.init))
    }

    /// The domain events, skipping unknown types.
    public func feedEvents() throws(MappingError) -> [FeedEvent] {
        try checkVersion(schemaVersion)
        var result: [FeedEvent] = []
        for event in events {
            if let feedEvent = try FeedEvent(event) { result.append(feedEvent) }
        }
        return result
    }
}

extension SnapshotDTO {
    public init(_ state: FireState, generatedAt: Date) {
        self.init(
            generatedAt: generatedAt,
            hotspots: state.hotspots.values.sorted { $0.id < $1.id }.map(HotspotDTO.init),
            drones: state.drones.values.sorted { $0.id < $1.id }.map(DroneDTO.init),
            perimeter: state.latestPerimeter.map(PerimeterDTO.init)
        )
    }

    /// The state the snapshot describes. Only the latest perimeter is included in snapshots.
    public func fireState() throws(MappingError) -> FireState {
        try checkVersion(schemaVersion)
        var hotspots: [Hotspot] = []
        for dto in self.hotspots { hotspots.append(try Hotspot(dto)) }
        var drones: [Drone] = []
        for dto in self.drones { drones.append(try Drone(dto)) }
        var perimeters: [FirePerimeter] = []
        if let perimeter { perimeters.append(try FirePerimeter(perimeter)) }
        return FireState(hotspots: hotspots, drones: drones, perimeters: perimeters)
    }
}

// MARK: Receipts

extension ReceiptDTO.Outcome {
    public init(_ outcome: SubmissionOutcome) {
        switch outcome {
        case .applied: self = .applied
        case .duplicate: self = .duplicate
        }
    }
}

extension SubmissionOutcome {
    public init(_ outcome: ReceiptDTO.Outcome) {
        switch outcome {
        case .applied: self = .applied
        case .duplicate: self = .duplicate
        }
    }
}
