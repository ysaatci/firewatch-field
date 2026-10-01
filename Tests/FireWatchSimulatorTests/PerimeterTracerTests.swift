import FireWatchCore
import Foundation
import TestSupport
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
        #expect(isClose(exact.areaSquareMetres, 40_000, within: 10))  // a 200 m square, corners at 1 cm precision
        let smoothed = FirePerimeter(time: .now, polygons: terrain.polygons(of: burned))
        #expect(smoothed.contains(centre))
        #expect(smoothed.areaSquareMetres < exact.areaSquareMetres)
    }

    /// A one-cell pocket that opens to the outside only through a corner is filled, so the
    /// outline doesn't detour into it (which smoothing drew as a small loop).
    @Test func smallCornerPocketIsFilled() throws {
        let picture = ".....\n.###.\n.#.#.\n.##..\n....."
        let polygons = PerimeterTracer.polygons(of: mask(picture), smoothing: 0, minimumHoleCells: 2)
        try #require(polygons.count == 1)
        let exterior = polygons[0].exterior
        #expect(Set(exterior).count == exterior.count, "the ring still visits the pinch corner twice")
        #expect(PerimeterTracer.signedArea(exterior) == 8)  // seven burned cells and the pocket
        // Without a minimum, the pocket stays out of the outline.
        #expect(PerimeterTracer.signedArea(trace(picture)[0].exterior) == 7)
    }

    /// Smoothing never makes a ring cross itself, even on ragged one-cell-wide shapes.
    @Test(arguments: 0..<400)
    func smoothedRingsAreSimple(seed: UInt64) {
        var random = SeededRandom(seed: seed)
        let burned = Grid(rows: 7, columns: 7) { _ in Double.random(in: 0..<1, using: &random) < 0.55 }
        for polygon in PerimeterTracer.polygons(of: burned, smoothing: 2) {
            let rings = [polygon.exterior] + polygon.holes
            for ring in rings {
                #expect(!Self.crossesItself(ring), "mask \(seed):\n\(Self.picture(of: burned))")
            }
            for i in rings.indices {
                for j in rings.indices where j > i {
                    #expect(!Self.cross(rings[i], rings[j]), "rings cross, mask \(seed):\n\(Self.picture(of: burned))")
                }
            }
        }
    }

    @Test func crossingCheckersSeeCrossings() {
        let bowTie = [(0, 0), (2, 2), (2, 0), (0, 2)].map { PlanarPoint(x: Double($0.0), y: Double($0.1)) }
        let square = [(0, 0), (2, 0), (2, 2), (0, 2)].map { PlanarPoint(x: Double($0.0), y: Double($0.1)) }
        let shifted = square.map { PlanarPoint(x: $0.x + 1, y: $0.y + 1) }
        #expect(Self.crossesItself(bowTie))
        #expect(!Self.crossesItself(square))
        #expect(Self.cross(square, shifted))
    }

    /// Whether any segment of one ring crosses or touches a segment of the other.
    static func cross(_ first: [PlanarPoint], _ second: [PlanarPoint]) -> Bool {
        func side(_ o: PlanarPoint, _ a: PlanarPoint, _ b: PlanarPoint) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        for i in first.indices {
            let (p, q) = (first[i], first[(i + 1) % first.count])
            for j in second.indices {
                let (r, s) = (second[j], second[(j + 1) % second.count])
                let d1 = side(r, s, p), d2 = side(r, s, q), d3 = side(p, q, r), d4 = side(p, q, s)
                if d1 * d2 <= 0, d3 * d4 <= 0, !(d1 == 0 && d2 == 0) { return true }
            }
        }
        return false
    }

    static func picture(of mask: Grid<Bool>) -> String {
        (0..<mask.rows).reversed().map { row in
            String((0..<mask.columns).map { mask.value(at: GridIndex(row: row, column: $0)) == true ? "#" : "." })
        }.joined(separator: "\n")
    }

    /// Whether two non-adjacent segments of the closed ring touch or cross.
    static func crossesItself(_ ring: [PlanarPoint]) -> Bool {
        let n = ring.count
        func cross(_ o: PlanarPoint, _ a: PlanarPoint, _ b: PlanarPoint) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        for i in 0..<n {
            for j in (i + 2)..<(n + i - 1) where j < n {
                let (p, q) = (ring[i], ring[(i + 1) % n])
                let (r, s) = (ring[j], ring[(j + 1) % n])
                let d1 = cross(r, s, p), d2 = cross(r, s, q), d3 = cross(p, q, r), d4 = cross(p, q, s)
                if (d1 > 1e-9) != (d2 > 1e-9), (d3 > 1e-9) != (d4 > 1e-9),
                    abs(d1) > 1e-9, abs(d2) > 1e-9, abs(d3) > 1e-9, abs(d4) > 1e-9
                {
                    return true
                }
            }
        }
        return false
    }
}
