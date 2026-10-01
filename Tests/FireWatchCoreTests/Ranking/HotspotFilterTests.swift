import Foundation
import TestSupport
import Testing

@testable import FireWatchCore

struct HotspotFilterTests {
    func hotspot(celsius: Double, after actions: [HotspotAction] = []) throws -> Hotspot {
        Hotspot(
            id: "hs", coordinate: .manavgat, confidence: 1,
            reading: TemperatureReading(time: .distantPast, celsius: celsius),
            workflow: try actions.reduce(.initial) { try $0.applying($1) })
    }

    @Test func openHidesOnlyVerifiedCold() throws {
        #expect(HotspotFilter.open.includes(try hotspot(celsius: 50)))
        #expect(HotspotFilter.open.includes(try hotspot(celsius: 50, after: [.extinguish])))
        #expect(!HotspotFilter.open.includes(try hotspot(celsius: 50, after: [.extinguish, .verifyCold])))
        #expect(HotspotFilter.everything.includes(try hotspot(celsius: 50, after: [.extinguish, .verifyCold])))
    }

    @Test func minimumSeverity() throws {
        let filter = HotspotFilter(statuses: Set(HotspotStatus.allCases), minimumSeverity: .high)
        #expect(!filter.includes(try hotspot(celsius: 150)))
        #expect(filter.includes(try hotspot(celsius: 250)))
    }

    @Test(arguments: [
        (0.0, CompassPoint.north), (22, .north), (23, .northEast), (90, .east), (180, .south), (269, .west),
        (337, .northWest), (338, .north), (-45, .northWest),
    ])
    func compassPoints(degrees: Double, expected: CompassPoint) {
        #expect(CompassPoint(degrees: degrees) == expected)
    }
}
