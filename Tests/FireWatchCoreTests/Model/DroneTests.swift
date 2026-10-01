import Foundation
import TestSupport
import Testing

@testable import FireWatchCore

struct DroneTests {
    func position(seconds: Double) -> DronePosition {
        DronePosition(
            time: Date(timeIntervalSince1970: seconds),
            coordinate: .manavgat,
            headingDegrees: 90,
            altitudeMetres: 120,
            battery: 0.9
        )
    }

    @Test func movesForwardInTime() {
        var drone = Drone(id: "d-1", name: "Kartal 1", position: position(seconds: 0))
        drone.move(to: position(seconds: 20))
        #expect(drone.position.time == Date(timeIntervalSince1970: 20))
        #expect(drone.track.count == 2)
    }

    @Test func ignoresStalePositions() {
        var drone = Drone(id: "d-1", name: "Kartal 1", position: position(seconds: 20))
        drone.move(to: position(seconds: 10))
        #expect(drone.position.time == Date(timeIntervalSince1970: 20))
        #expect(drone.track.count == 1)
    }

    @Test func trackIsCapped() {
        var drone = Drone(id: "d-1", name: "Kartal 1", position: position(seconds: 0))
        for second in 1...100 { drone.move(to: position(seconds: Double(second))) }
        #expect(drone.track.count == Drone.trackLimit)
        #expect(drone.position.time == Date(timeIntervalSince1970: 100))
    }
}

struct SightingReportTests {
    @Test func generatesUniqueIDs() {
        let make = {
            SightingReport(
                createdAt: .now, coordinate: .manavgat, severity: .high, note: "Smoke behind ridge")
        }
        #expect(make().id != make().id)
    }
}
