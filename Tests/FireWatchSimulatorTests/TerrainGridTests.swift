import FireWatchCore
import Testing

@testable import FireWatchSimulator

struct GridTests {
    @Test func storesRowMajorAndIterates() {
        var grid = Grid(rows: 2, columns: 3) { $0.row * 10 + $0.column }
        grid[GridIndex(row: 1, column: 2)] = 99
        #expect(grid.values == [0, 1, 2, 10, 11, 99])
        #expect(Array(grid.indices) == grid.indices.sorted())
        #expect(grid.value(at: GridIndex(row: 2, column: 0)) == nil)
        #expect(grid.value(at: GridIndex(row: -1, column: 0)) == nil)
    }
}

struct TerrainGridTests {
    let centre = Coordinate(latitude: 36.787, longitude: 31.443)

    func generate(seed: UInt64) -> TerrainGrid {
        var random = SeededRandom(seed: seed)
        return TerrainGrid.generate(rows: 60, columns: 80, cellSize: 50, centre: centre, random: &random)
    }

    @Test func deterministicForSeed() {
        #expect(generate(seed: 1).fuel == generate(seed: 1).fuel)
        #expect(generate(seed: 1).fuel != generate(seed: 2).fuel)
    }

    @Test func fuelHasBareGroundAndBurnableRange() {
        let fuel = generate(seed: 1).fuel.values
        let bare = fuel.filter { $0 == 0 }.count
        #expect(bare > 0 && bare < fuel.count / 2)
        #expect(fuel.allSatisfy { $0 == 0 || (0.3...1).contains($0) })
    }

    @Test func elevationWithinBounds() {
        #expect(generate(seed: 1).elevation.values.allSatisfy { (0...400).contains($0) })
    }

    @Test func noiseIsSmooth() {
        // Neighbouring cells differ by a small fraction of the 400 m range.
        let elevation = generate(seed: 1).elevation
        let steps = elevation.indices.compactMap { index in
            elevation.value(at: index.offset(rows: 0, columns: 1)).map { abs($0 - elevation[index]) }
        }
        #expect(steps.max() ?? 1 < 40)
    }

    @Test func cellLookupRoundTrips() {
        let terrain = generate(seed: 1)
        for index in [GridIndex(row: 0, column: 0), GridIndex(row: 59, column: 79), GridIndex(row: 30, column: 12)] {
            #expect(terrain.cell(containing: terrain.centre(of: index)) == index)
        }
        #expect(terrain.cell(containing: PlanarPoint(x: 0, y: 2_000)) == nil)
        #expect(terrain.centre(of: GridIndex(row: 30, column: 40)).distance(to: centre) < 50)
    }
}
