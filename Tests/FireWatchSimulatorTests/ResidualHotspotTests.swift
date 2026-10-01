import FireWatchCore
import TestSupport
import Testing

@testable import FireWatchSimulator

struct ResidualHotspotTests {
    let ambient = 30.0

    func hotspot(flareUpAt flareMinute: Double? = nil) -> ResidualHotspot {
        ResidualHotspot(
            id: "hs",
            coordinate: Coordinate(latitude: 0, longitude: 0),
            smoulder: CoolingCurve(startMinute: 10, peakCelsius: 430, coolingMinutes: 50),
            flareUp: flareMinute.map { CoolingCurve(startMinute: $0, peakCelsius: 330, coolingMinutes: 40) }
        )
    }

    @Test func absentBeforeAppearing() {
        #expect(hotspot().celsius(atMinute: 9, ambient: ambient) == nil)
        #expect(hotspot().celsius(atMinute: 10, ambient: ambient) == 430)
    }

    @Test func coolsExponentiallyTowardsAmbient() throws {
        // After one cooling time the excess over ambient has fallen by e.
        let afterOne = try #require(hotspot().celsius(atMinute: 60, ambient: ambient))
        #expect(isClose(afterOne, ambient + 400 / 2.718_281_828, within: 0.01))
        let muchLater = try #require(hotspot().celsius(atMinute: 2_000, ambient: ambient))
        #expect(isClose(muchLater, ambient, within: 0.01))
    }

    @Test func flareUpReheats() throws {
        let spot = hotspot(flareUpAt: 300)
        let before = try #require(spot.celsius(atMinute: 299, ambient: ambient))
        let after = try #require(spot.celsius(atMinute: 300, ambient: ambient))
        #expect(before < 40)
        #expect(after == 330)
    }

    @Test func modelLeavesHotspotsWhereCellsBurnedOut() {
        let terrain = TerrainGrid(
            cellSize: 50,
            centre: Coordinate(latitude: 36.787, longitude: 31.443),
            fuel: Grid(rows: 41, columns: 41, repeating: 1),
            elevation: Grid(rows: 41, columns: 41, repeating: 0)
        )
        var random = SeededRandom(seed: 1)
        let history = FireSpreadModel(wind: .calm).run(
            on: terrain, ignitions: [GridIndex(row: 20, column: 20)], minutes: 120, random: &random)
        var model = ResidualHotspotModel()
        model.smoulderChance = 0.5
        let hotspots = model.hotspots(from: history, on: terrain, random: &random)

        let burnedOut = history.burnedOutAt.values.compactMap { $0 }.count
        #expect(hotspots.count > burnedOut / 4 && hotspots.count < burnedOut * 3 / 4)
        #expect(Set(hotspots.map(\.id)).count == hotspots.count)
        for spot in hotspots {
            let cell = terrain.cell(containing: spot.coordinate)
            #expect(cell.flatMap { history.burnedOutAt[$0] }.map(Double.init) == spot.appearsAtMinute)
        }
        let flared = hotspots.filter { $0.flareUp != nil }.count
        #expect(flared > 0 && flared < hotspots.count)
    }
}
