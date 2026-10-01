import FireWatchCore
import Testing

@testable import FireWatchSimulator

struct FireSpreadModelTests {
    let centre = Coordinate(latitude: 36.787, longitude: 31.443)
    let middle = GridIndex(row: 30, column: 30)

    func flatTerrain(fuel: Double = 1) -> TerrainGrid {
        TerrainGrid(
            cellSize: 50,
            centre: centre,
            fuel: Grid(rows: 61, columns: 61, repeating: fuel),
            elevation: Grid(rows: 61, columns: 61, repeating: 0)
        )
    }

    func burn(_ terrain: TerrainGrid, wind: Wind = .calm, minutes: Int = 60, seed: UInt64 = 1) -> FireHistory {
        var random = SeededRandom(seed: seed)
        return FireSpreadModel(wind: wind).run(on: terrain, ignitions: [middle], minutes: minutes, random: &random)
    }

    /// How many columns east and west of the ignition point the fire reached.
    func reach(_ history: FireHistory) -> (east: Int, west: Int) {
        let columns = history.ignitedAt.indices.filter { history.ignitedAt[$0] != nil }.map(\.column)
        return ((columns.max() ?? middle.column) - middle.column, middle.column - (columns.min() ?? middle.column))
    }

    @Test func nothingBurnsWithoutFuel() {
        let history = burn(flatTerrain(fuel: 0))
        #expect(history.ignitedAt.values.allSatisfy { $0 == nil })
    }

    @Test func spreadsFromIgnition() {
        let history = burn(flatTerrain())
        #expect(history.ignitedAt[middle] == 0)
        #expect(history.ignitedAt.values.compactMap { $0 }.count > 50)
    }

    @Test func westerlyWindPushesFireEast() {
        let history = burn(flatTerrain(), wind: Wind(speed: 10, fromDegrees: 270), minutes: 40)
        let reach = reach(history)
        #expect(reach.east > reach.west * 2)
    }

    @Test func fireRunsUphill() {
        let base = flatTerrain()
        let slope = TerrainGrid(
            cellSize: 50,
            centre: centre,
            fuel: base.fuel,
            elevation: Grid(rows: 61, columns: 61) { Double($0.column) * 10 }  // rises eastward
        )
        let reach = reach(burn(slope, minutes: 40))
        #expect(reach.east > reach.west)
    }

    @Test func cellsBurnOutAfterIgniting() {
        let history = burn(flatTerrain(), minutes: 90)
        #expect(history.burnedOutAt[middle] != nil)
        for index in history.ignitedAt.indices {
            if let ignited = history.ignitedAt[index], let out = history.burnedOutAt[index] {
                #expect(out > ignited)
            }
            if history.burnedOutAt[index] != nil { #expect(history.ignitedAt[index] != nil) }
        }
    }

    @Test func deterministicForSeed() {
        #expect(burn(flatTerrain(), seed: 5) == burn(flatTerrain(), seed: 5))
        #expect(burn(flatTerrain(), seed: 5) != burn(flatTerrain(), seed: 6))
    }

    @Test func affectedMaskGrowsOverTime() {
        let history = burn(flatTerrain())
        let early = history.affectedMask(atMinute: 10).values.filter { $0 }.count
        let late = history.affectedMask(atMinute: 60).values.filter { $0 }.count
        #expect(early >= 1 && late > early)
        #expect(history.hasIgnited(middle, by: 0))
    }
}
