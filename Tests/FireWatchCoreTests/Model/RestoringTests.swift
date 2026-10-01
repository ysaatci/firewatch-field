import Foundation
import TestSupport
import Testing

@testable import FireWatchCore

struct RestoringTests {
    @Test(arguments: [
        (HotspotStatus.new, 0, true), (.new, 1, false),
        (.flaredUp, 0, false), (.flaredUp, 2, true),
        (.assigned, 0, true), (.extinguished, 3, true), (.verifiedCold, -1, false),
    ])
    func workflowRestoresOnlyReachableStates(status: HotspotStatus, flareUps: Int, reachable: Bool) {
        let workflow = HotspotWorkflow(restoring: status, flareUps: flareUps)
        #expect((workflow != nil) == reachable)
        #expect(workflow.map { $0.status == status && $0.flareUps == flareUps } ?? true)
    }

    @Test func restoredWorkflowEqualsTheOneReachedByActions() throws {
        let reached = try HotspotWorkflow.initial.applying(.extinguish).applying(.flareUp).applying(.assign)
        #expect(HotspotWorkflow(restoring: .assigned, flareUps: 1) == reached)
    }

    @Test func hotspotRestoresHistoryAndEarlierFirstSeen() throws {
        let start = Date(timeIntervalSince1970: 0)
        let readings = (1...60).map {
            TemperatureReading(time: start.addingTimeInterval(Double($0) * 60), celsius: 100)
        }
        let hotspot = try #require(
            Hotspot(
                id: "hs", coordinate: .manavgat, confidence: 0.7, firstSeen: start, readings: readings,
                workflow: .initial))
        #expect(hotspot.firstSeen == start)
        #expect(hotspot.readings.count == Hotspot.historyLimit)
        #expect(hotspot.lastSeen == readings[59].time)
        #expect(
            Hotspot(id: "hs", coordinate: .manavgat, confidence: 1, firstSeen: start, readings: [], workflow: .initial)
                == nil)
    }

    @Test func fireStateRestoresSortedPerimeters() {
        let late = FirePerimeter(time: Date(timeIntervalSince1970: 20), polygons: [])
        let early = FirePerimeter(time: Date(timeIntervalSince1970: 10), polygons: [])
        let state = FireState(hotspots: [], drones: [], perimeters: [late, early])
        #expect(state.perimeters == [early, late])
    }
}
