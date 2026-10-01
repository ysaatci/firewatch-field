import FireWatchCore
import Foundation
import Testing

@testable import FireWatchSimulator

struct PerimeterTracerTests {
    /// A mask from rows of text, top row first: `#` is burned.
    func mask(_ picture: String) -> Grid<Bool> {
        let lines = picture.split(separator: "\n").map(Array.init).reversed().map { $0 }
        return Grid(rows: lines.count, columns: lines[0].count) { lines[$0.row][$0.column] == "#" }
    }

    func trace(_ picture: String) -> [LatticePolygon] {
        PerimeterTracer.polygons(of: mask(picture), smoothing: 0, minimumHoleCells: 0)
    }

    @Test func emptyMaskHasNoPolygons() {
        #expect(trace("...\n...").isEmpty)
    }

    @Test func singleCellIsUnitSquare() throws {
        let polygons = trace("...\n.#.\n...")
        try #require(polygons.count == 1)
        #expect(Set(polygons[0].exterior.map { [$0.x, $0.y] }) == [[1, 1], [2, 1], [2, 2], [1, 2]])
        #expect(PerimeterTracer.signedArea(polygons[0].exterior) == 1)
    }

    @Test func lShapeKeepsOnlyCorners() throws {
        let polygons = trace("#..\n#..\n###")
        try #require(polygons.count == 1)
        #expect(polygons[0].exterior.count == 6)
        #expect(PerimeterTracer.signedArea(polygons[0].exterior) == 5)
    }

    @Test func ringWithIslandHasHole() throws {
        let polygons = trace("###\n#.#\n###")
        try #require(polygons.count == 1)
        #expect(polygons[0].holes.count == 1)
        #expect(PerimeterTracer.signedArea(polygons[0].holes[0]) == -1)
    }

    @Test func separateAndDiagonalAreasAreSeparatePolygons() {
        #expect(trace("#..#\n....\n#..#").count == 4)
        #expect(trace("#.\n.#").count == 2)
    }

    @Test func cellsOnGridEdgeAreClosed() {
        #expect(trace("##\n##").map { PerimeterTracer.signedArea($0.exterior) } == [4])
    }

    @Test func nestedIslandBelongsToInnermostFire() throws {
        let polygons = trace(
            """
            #######
            #.....#
            #.###.#
            #.#.#.#
            #.###.#
            #.....#
            #######
            """
        )
        try #require(polygons.count == 2)
        #expect(polygons.allSatisfy { $0.holes.count == 1 })
    }

    @Test func smallHolesAreDropped() {
        let polygons = PerimeterTracer.polygons(of: mask("###\n#.#\n###"), smoothing: 0, minimumHoleCells: 2)
        #expect(polygons[0].holes.isEmpty)
    }

    @Test func smoothingRoundsCornersButKeepsArea() {
        let square = [
            PlanarPoint(x: 0, y: 0), PlanarPoint(x: 4, y: 0), PlanarPoint(x: 4, y: 4), PlanarPoint(x: 0, y: 4),
        ]
        let smoothed = PerimeterTracer.smooth(square, iterations: 2)
        #expect(smoothed.count == 16)
        #expect(isClose(PerimeterTracer.signedArea(smoothed), 16, within: 3))
        #expect(smoothed.allSatisfy { (0...4).contains($0.x) && (0...4).contains($0.y) })
    }

    @Test func terrainPerimeterIsInCoordinates() {
        let centre = Coordinate(latitude: 36.787, longitude: 31.443)
        let terrain = TerrainGrid(
            cellSize: 50,
            centre: centre,
            fuel: Grid(rows: 10, columns: 10, repeating: 1),
            elevation: Grid(rows: 10, columns: 10, repeating: 0)
        )
        let burned = Grid(rows: 10, columns: 10) { (3...6).contains($0.row) && (3...6).contains($0.column) }
        let exact = FirePerimeter(time: .now, polygons: terrain.polygons(of: burned, smoothing: 0))
        #expect(exact.contains(centre))
        #expect(isClose(exact.areaSquareMetres, 40_000, within: 1))  // a 200 m square
        let smoothed = FirePerimeter(time: .now, polygons: terrain.polygons(of: burned))
        #expect(smoothed.contains(centre))
        #expect(smoothed.areaSquareMetres < exact.areaSquareMetres)
    }
}

func isClose(_ a: Double, _ b: Double, within tolerance: Double) -> Bool {
    abs(a - b) <= tolerance
}
