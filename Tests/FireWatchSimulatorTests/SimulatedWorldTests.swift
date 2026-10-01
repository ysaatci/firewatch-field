import FireWatchCore
import Foundation
import Testing

@testable import FireWatchSimulator

struct SimulatedWorldTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var world: SimulatedWorld { SimulatedWorld(scenario: ScenarioTests.scenario, start: start) }

    func at(_ minute: Double) -> Date { start.addingTimeInterval(minute * 60) }

    @Test func eventsAreInRangeAndInOrder() {
        let events = world.events(from: at(30), to: at(60))
        #expect(!events.isEmpty)
        #expect(events.allSatisfy { $0.time >= at(30) && $0.time < at(60) })
        #expect(events.map(\.time) == events.map(\.time).sorted())
    }

    @Test func consecutiveWindowsCoverEverythingOnce() {
        let whole = world.events(from: at(0), to: world.end.addingTimeInterval(1))
        let pieces = stride(from: 0.0, through: 180, by: 7).flatMap { world.events(from: at($0), to: at($0 + 7)) }
        #expect(pieces == whole)
    }

    @Test func replayingEverythingKnowsEveryDetectedHotspot() {
        let state = FireState(events: world.events(from: at(0), to: world.end.addingTimeInterval(1)))
        #expect(state.hotspots.count == Set(ScenarioTests.scenario.passes.map(\.hotspot)).count)
        #expect(state.drones.count == 3)
        #expect(state.perimeters.count == ScenarioTests.scenario.perimeters.count)
    }

    @Test func extinguishedHotspotReadsCool() throws {
        let scenario = ScenarioTests.scenario
        let spot = try #require(scenario.hotspots.first { $0.flareUp == nil })
        var world = world
        let putOut = spot.appearsAtMinute + 1
        world.intervene(HotspotCommand(hotspotID: spot.id, action: .extinguish, issuedAt: at(putOut)))
        let later = try #require(world.celsius(of: spot, atMinute: putOut + 10))
        #expect(later < 40)
        #expect(try #require(world.celsius(of: spot, atMinute: putOut - 0.5)) > 100)
    }

    @Test func otherCommandsChangeNothing() throws {
        let spot = try #require(ScenarioTests.scenario.hotspots.first)
        var world = world
        world.intervene(HotspotCommand(hotspotID: spot.id, action: .assign, issuedAt: at(spot.appearsAtMinute)))
        let minute = spot.appearsAtMinute + 5
        #expect(world.celsius(of: spot, atMinute: minute) == spot.celsius(atMinute: minute, ambient: 30))
    }

    @Test func scheduledFlareUpSurvivesExtinguishing() throws {
        let spot = try #require(ScenarioTests.scenario.hotspots.first { $0.flareUp != nil })
        let flareUp = try #require(spot.flareUp)
        var world = world
        world.intervene(HotspotCommand(hotspotID: spot.id, action: .extinguish, issuedAt: at(spot.appearsAtMinute + 1)))
        #expect(try #require(world.celsius(of: spot, atMinute: flareUp.startMinute - 1)) < 40)
        #expect(try #require(world.celsius(of: spot, atMinute: flareUp.startMinute)) >= 200)

        // Putting it out again after the flare-up keeps it out.
        world.intervene(HotspotCommand(hotspotID: spot.id, action: .extinguish, issuedAt: at(flareUp.startMinute + 1)))
        #expect(try #require(world.celsius(of: spot, atMinute: flareUp.startMinute + 20)) < 40)
    }

    @Test func partitioningIndexFindsBoundary() {
        #expect([1, 3, 5, 7].partitioningIndex { $0 >= 4 } == 2)
        #expect([1, 3].partitioningIndex { $0 >= 9 } == 2)
        #expect([Int]().partitioningIndex { $0 >= 0 } == 0)
    }
}
