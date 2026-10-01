import FireWatchCore
import Foundation
import Testing

@testable import FireWatchSimulator

struct ScenarioTests {
    static let configuration = ScenarioConfiguration(
        seed: 42, centre: Coordinate(latitude: 36.787, longitude: 31.443), rows: 80, columns: 80, minutes: 180)
    static let scenario = Scenario(configuration)

    var scenario: Scenario { Self.scenario }

    /// A compact fingerprint of the scenario for golden comparisons.
    static func summary(_ scenario: Scenario) -> String {
        let ignited = scenario.fire.ignitedAt.values.compactMap { $0 }.count
        let detected = Set(scenario.passes.map(\.hotspot)).count
        let flareUps = scenario.hotspots.filter { $0.flareUp != nil }.count
        let lastArea = scenario.perimeters.last?.areaSquareMetres
        return [
            "ignited=\(ignited)",
            "hotspots=\(scenario.hotspots.count)",
            "flareUps=\(flareUps)",
            "detected=\(detected)",
            "passes=\(scenario.passes.count)",
            "perimeters=\(scenario.perimeters.count)",
            "areaHa=\(Int((lastArea ?? 0) / 10_000))",
        ].joined(separator: " ")
    }

    @Test func sameConfigurationSameScenario() {
        let again = Scenario(Self.configuration)
        #expect(again.hotspots == scenario.hotspots)
        #expect(again.passes == scenario.passes)
        #expect(again.perimeters == scenario.perimeters)
    }

    @Test func differentSeedDifferentScenario() {
        var configuration = Self.configuration
        configuration.seed = 43
        #expect(Scenario(configuration).hotspots != scenario.hotspots)
    }

    /// Guards against accidental behaviour changes. If a change is intended, update the expected string.
    @Test func goldenSummary() {
        #expect(
            Self.summary(scenario)
                == "ignited=1985 hotspots=278 flareUps=69 detected=232 passes=923 perimeters=37 areaHa=501")
    }

    @Test func fireGrowsOverTime() {
        let areas = scenario.perimeters.map { $0.areaSquareMetres }
        #expect(areas.first ?? 0 < 10_000)
        #expect(areas.last ?? 0 > 1_000_000)  // over 100 ha after three hours
        #expect(zip(areas, areas.dropFirst()).filter { $1 < $0 * 0.95 }.isEmpty)
        #expect(scenario.perimeters.map(\.minute) == Array(stride(from: 0, through: 180, by: 5)))
    }

    @Test func dronesDetectMostHotspots() {
        let detected = Set(scenario.passes.map(\.hotspot)).count
        #expect(scenario.hotspots.count > 20)
        #expect(detected > scenario.hotspots.count / 2)
    }
}
