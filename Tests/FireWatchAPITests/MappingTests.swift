import FireWatchCore
import FireWatchSimulator
import Foundation
import Testing

@testable import FireWatchAPI

struct MappingTests {
    /// A small simulated fire, played to the end, as realistic test data.
    static let world: SimulatedWorld = {
        let configuration = ScenarioConfiguration(
            seed: 7, centre: Coordinate(latitude: 36.83, longitude: 31.47), rows: 60, columns: 60, minutes: 120)
        return SimulatedWorld(scenario: Scenario(configuration), start: Date(timeIntervalSince1970: 1_800_000_000))
    }()
    static let events = world.events(from: world.start, to: world.end.addingTimeInterval(1))

    func overTheWire<T: Codable>(_ value: T) throws -> T {
        try API.makeDecoder().decode(T.self, from: API.makeEncoder().encode(value))
    }

    @Test func eventsSurviveTheWire() throws {
        let batch = try overTheWire(EventBatchDTO(Self.events))
        #expect(try batch.feedEvents() == Self.events)
    }

    @Test func snapshotSurvivesTheWire() throws {
        var state = FireState(events: Self.events)
        let hotspot = try #require(state.hotspots.keys.min())
        try state.execute(HotspotCommand(hotspotID: hotspot, action: .assign, issuedAt: Self.world.end))

        let restored = try overTheWire(SnapshotDTO(state, generatedAt: Self.world.end)).fireState()
        #expect(restored.hotspots == state.hotspots)
        #expect(restored.drones == state.drones)
        #expect(restored.latestPerimeter == state.latestPerimeter)
        #expect(restored.hotspots[hotspot]?.status == .assigned)
    }

    @Test func perimeterRingsAreClosedOnTheWireAndOpenInTheDomain() throws {
        let perimeter = try #require(FireState(events: Self.events).latestPerimeter)
        let dto = PerimeterDTO(perimeter)
        guard case .multiPolygon(let polygons) = dto.geometry else {
            Issue.record("expected MultiPolygon")
            return
        }
        #expect(polygons.allSatisfy { $0.allSatisfy { $0.first == $0.last } })
        #expect(try FirePerimeter(dto) == perimeter)
        #expect(isClose(dto.properties.areaHectares, perimeter.areaSquareMetres / 10_000, within: 1e-9))
    }

    @Test func plainPolygonPerimetersAreAccepted() throws {
        let ring = [
            Position(longitude: 0, latitude: 0), Position(longitude: 1, latitude: 0),
            Position(longitude: 1, latitude: 1), Position(longitude: 0, latitude: 0),
        ]
        let dto = PerimeterDTO(geometry: .polygon([ring]), properties: PerimeterProperties(time: .now, areaHectares: 0))
        #expect(try FirePerimeter(dto).polygons.first?.exterior.count == 3)
        let point = PerimeterDTO(geometry: .point(ring[0]), properties: dto.properties)
        #expect(throws: MappingError.notAPerimeter) { try FirePerimeter(point) }
    }

    @Test func rejectsUnknownSchemaVersions() {
        #expect(throws: MappingError.unsupportedSchemaVersion(2)) {
            try EventBatchDTO(schemaVersion: 2, events: []).feedEvents()
        }
        #expect(throws: MappingError.unsupportedSchemaVersion(0)) {
            try SnapshotDTO(schemaVersion: 0, generatedAt: .now, hotspots: [], drones: [], perimeter: nil).fireState()
        }
    }

    @Test func skipsUnknownEventTypes() throws {
        #expect(try EventBatchDTO(events: [.unknown(type: "windChanged")]).feedEvents().isEmpty)
    }

    @Test func rejectsInvalidEnumerationsAndShapes() {
        let hotspot = HotspotDTO(
            id: "hs", location: Position(longitude: 0, latitude: 0), confidence: 1, firstSeen: .now, status: "new",
            flareUps: 0, readings: [ReadingDTO(time: .now, celsius: 100)])
        var badStatus = hotspot
        badStatus.status = "burning"
        #expect(throws: MappingError.unknownStatus("burning")) { try Hotspot(badStatus) }
        var unreachable = hotspot
        unreachable.flareUps = 2
        #expect(throws: MappingError.unreachableWorkflow(status: "new", flareUps: 2)) { try Hotspot(unreachable) }
        var empty = hotspot
        empty.readings = []
        #expect(throws: MappingError.noReadings(hotspotID: "hs")) { try Hotspot(empty) }

        #expect(throws: MappingError.unknownAction("douse")) {
            try HotspotCommand(CommandDTO(id: "c", hotspotID: "hs", action: "douse", issuedAt: .now))
        }
        #expect(throws: MappingError.noTrack(droneID: "d")) { try Drone(DroneDTO(id: "d", name: "n", track: [])) }
        #expect(throws: MappingError.unknownSeverity("huge")) { try Severity(name: "huge") }
    }

    @Test func reportsMapBothWays() throws {
        let report = SightingReport(
            createdAt: Date(timeIntervalSince1970: 1_800_000_000), coordinate: Coordinate(latitude: 1, longitude: 2),
            severity: .extreme, note: "Flames on the ridge")
        let dto = ReportDTO(report, photoJPEG: Data([0xFF, 0xD8]))
        #expect(dto.severity == "extreme")
        #expect(try SightingReport(overTheWire(dto)) == report)
    }
}

func isClose(_ a: Double, _ b: Double, within tolerance: Double) -> Bool {
    abs(a - b) <= tolerance
}
