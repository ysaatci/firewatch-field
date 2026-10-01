import FireWatchCore
import Testing

@testable import FireWatchSimulator

struct ScenarioPresetTests {
    func detectedCount(_ scenario: Scenario) -> Int {
        Set(scenario.passes.map(\.hotspot)).count
    }

    @Test func defaultIsManavgat() {
        #expect(ScenarioPreset.default == .manavgat)
        #expect(ScenarioPreset(rawValue: "stress") == .stress)
    }

    @Test func manavgatFireStaysOnTheMap() {
        let scenario = Scenario(ScenarioPreset.manavgat.configuration)
        let edges = scenario.fire.ignitedAt.indices.filter { index in
            index.row == 0 || index.column == 0 || index.row == scenario.terrain.rows - 1
                || index.column == scenario.terrain.columns - 1
        }
        #expect(edges.allSatisfy { scenario.fire.ignitedAt[$0] == nil })
        #expect((150...400).contains(detectedCount(scenario)))
    }

    @Test func stressLeavesOverTwoThousandDetectedHotspots() {
        #expect(detectedCount(Scenario(ScenarioPreset.stress.configuration)) >= 2_000)
    }
}
