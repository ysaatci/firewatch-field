import FireWatchCore
import FireWatchSimulator
import Foundation
import Testing

@testable import FireWatchServer

struct FireSimulationTests {
    func makeSimulation(clock: TestClock, startMinute: Double = 60) -> FireSimulation {
        FireSimulation(preset: .manavgat, speed: 60, startMinute: startMinute, now: { clock.now })
    }

    @Test func startsWithHistoryUpToStartMinute() async {
        let clock = TestClock()
        let simulation = makeSimulation(clock: clock)
        let state = await simulation.state
        #expect(!state.drones.isEmpty)
        #expect(state.latestPerimeter != nil)
        // Scenario time lines up with the wall clock at the start.
        #expect(abs(await simulation.scenarioNow.timeIntervalSince(clock.now)) < 1)
    }

    @Test func advanceHandsOutEachEventOnce() async {
        let clock = TestClock()
        let simulation = makeSimulation(clock: clock, startMinute: 0)
        var all: [FeedEvent] = []
        for _ in 0..<20 {
            clock.advance(seconds: 7)
            all += await simulation.advance()
        }
        #expect(await simulation.advance().isEmpty)

        let scenario = Scenario(ScenarioPreset.manavgat.configuration)
        let world = SimulatedWorld(
            scenario: scenario, start: await simulation.scenarioNow.addingTimeInterval(-140 * 60))
        #expect(all == world.events(fromMinute: 0, toMinute: 140))
        #expect(await simulation.state == FireState(events: all))
    }
}
