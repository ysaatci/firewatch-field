import Foundation
import Testing

@testable import FireWatchAPI

struct DTOTests {
    /// A date with whole milliseconds, which the wire format preserves exactly.
    let time = Date(timeIntervalSince1970: 1_800_000_000.125)
    let location = Position(longitude: 31.47, latitude: 36.83)

    func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try API.makeDecoder().decode(T.self, from: API.makeEncoder().encode(value))
    }

    func json(_ value: some Encodable) throws -> String {
        String(decoding: try API.makeEncoder().encode(value), as: UTF8.self)
    }

    var observation: ObservationDTO {
        ObservationDTO(
            hotspotID: "hs-1", location: location, time: time, celsius: 312.5, confidence: 0.8, droneID: "drone-1")
    }

    @Test func datesAreISO8601WithMilliseconds() throws {
        #expect(try json(ReadingDTO(time: time, celsius: 1)) == #"{"celsius":1,"time":"2027-01-15T08:00:00.125Z"}"#)
    }

    @Test func acceptsDatesWithoutFractionalSeconds() throws {
        let data = Data(#"{"celsius":1,"time":"2027-01-15T08:00:00Z"}"#.utf8)
        let reading = try API.makeDecoder().decode(ReadingDTO.self, from: data)
        #expect(reading.time == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func rejectsMalformedDates() {
        let data = Data(#"{"celsius":1,"time":"yesterday"}"#.utf8)
        #expect(throws: DecodingError.self) { try API.makeDecoder().decode(ReadingDTO.self, from: data) }
    }

    @Test func snapshotRoundTrips() throws {
        let snapshot = SnapshotDTO(
            generatedAt: time,
            hotspots: [
                HotspotDTO(
                    id: "hs-1", location: location, confidence: 0.9, firstSeen: time, status: "new", flareUps: 0,
                    readings: [ReadingDTO(time: time, celsius: 400)])
            ],
            drones: [
                DroneDTO(
                    id: "drone-1", name: "Kartal-1",
                    track: [
                        DronePositionDTO(
                            time: time, location: location, headingDegrees: 90, altitudeMetres: 120, battery: 0.7)
                    ])
            ],
            perimeter: Feature(
                geometry: .multiPolygon([[[location, location]]]),
                properties: PerimeterProperties(time: time, areaHectares: 12.5))
        )
        #expect(try roundTrip(snapshot) == snapshot)
        #expect(snapshot.schemaVersion == API.schemaVersion)
    }

    @Test(arguments: [
        EventDTO.hotspotObserved(
            ObservationDTO(
                hotspotID: "hs-1", location: Position(longitude: 1, latitude: 2), time: .distantPast, celsius: 1,
                confidence: 0.5, droneID: "d")),
        .hotspotCommandApplied(CommandDTO(id: "c-1", hotspotID: "hs-1", action: "assign", issuedAt: .distantPast)),
        .droneMoved(
            DroneUpdateDTO(
                droneID: "d", name: "Kartal-1",
                position: DronePositionDTO(
                    time: .distantPast, location: Position(longitude: 1, latitude: 2), headingDegrees: 0,
                    altitudeMetres: 120, battery: 1))),
    ])
    func eventsRoundTrip(event: EventDTO) throws {
        #expect(try roundTrip(event) == event)
    }

    @Test func eventsAreTaggedWithTypeAndData() throws {
        let text = try json(EventDTO.hotspotObserved(observation))
        #expect(text.hasPrefix(#"{"data":{"#))
        #expect(text.hasSuffix(#""type":"hotspotObserved"}"#))
    }

    @Test func unknownEventTypesAreKeptNotFatal() throws {
        let data = Data(
            #"{"schemaVersion":1,"events":[{"type":"windChanged","data":{"speed":9}},{"type":"droneMoved","data":{"droneID":"d","name":"n","position":{"time":"2027-01-15T08:00:00Z","location":[1,2],"headingDegrees":0,"altitudeMetres":1,"battery":1}}}]}"#
                .utf8)
        let batch = try API.makeDecoder().decode(EventBatchDTO.self, from: data)
        #expect(batch.events.count == 2)
        #expect(batch.events[0] == .unknown(type: "windChanged"))
    }

    @Test func reportPhotoIsBase64() throws {
        let report = ReportDTO(
            id: "r-1", createdAt: time, location: location, severity: "high", note: "Smoke", photoJPEG: Data([1, 2, 3]))
        #expect(try json(report).contains(#""photoJPEG":"AQID""#))
        #expect(try roundTrip(report) == report)
    }

    @Test func receiptsAndErrorsRoundTrip() throws {
        let receipt = ReceiptDTO(id: "c-1", outcome: .duplicate)
        #expect(try json(receipt) == #"{"id":"c-1","outcome":"duplicate"}"#)
        let error = ErrorDTO(code: "notAllowed", message: "verifyCold is not allowed from new")
        #expect(try roundTrip(error) == error)
    }
}
