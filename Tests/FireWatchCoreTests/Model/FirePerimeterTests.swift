import Foundation
import TestSupport
import Testing

@testable import FireWatchCore

struct FirePerimeterTests {
    let projection = LocalProjection(origin: .manavgat)

    /// An axis-aligned square ring, `size` metres wide, with its south-west corner at (`x`, `y`).
    func square(x: Double, y: Double, size: Double) -> [Coordinate] {
        [(x, y), (x + size, y), (x + size, y + size), (x, y + size)]
            .map { projection.unproject(PlanarPoint(x: $0.0, y: $0.1)) }
    }

    func point(_ x: Double, _ y: Double) -> Coordinate {
        projection.unproject(PlanarPoint(x: x, y: y))
    }

    @Test func squareContainsInteriorOnly() {
        let polygon = Polygon(exterior: square(x: 0, y: 0, size: 1_000))
        #expect(polygon.contains(point(500, 500)))
        #expect(!polygon.contains(point(1_500, 500)))
        #expect(!polygon.contains(point(500, -10)))
    }

    @Test func holesAreExcluded() {
        let polygon = Polygon(
            exterior: square(x: 0, y: 0, size: 1_000), holes: [square(x: 400, y: 400, size: 200)])
        #expect(!polygon.contains(point(500, 500)))
        #expect(polygon.contains(point(100, 100)))
    }

    @Test func concaveRing() {
        // An L shape: the notch at the top right is outside.
        let ring = [(0.0, 0.0), (1_000, 0), (1_000, 500), (500, 500), (500, 1_000), (0, 1_000)].map(point)
        let polygon = Polygon(exterior: ring)
        #expect(polygon.contains(point(250, 750)))
        #expect(!polygon.contains(point(750, 750)))
        #expect(isClose(polygon.areaSquareMetres, 750_000, within: 100))
    }

    @Test func areaSubtractsHoles() {
        let polygon = Polygon(
            exterior: square(x: 0, y: 0, size: 1_000), holes: [square(x: 100, y: 100, size: 100)])
        #expect(isClose(polygon.areaSquareMetres, 990_000, within: 100))
    }

    @Test func degenerateRingsHaveNoArea() {
        #expect(Polygon(exterior: []).areaSquareMetres == 0)
        #expect(Polygon(exterior: [.manavgat, .london]).areaSquareMetres == 0)
    }

    @Test func perimeterCombinesSpotFires() throws {
        let perimeter = FirePerimeter(
            time: Date(timeIntervalSince1970: 0),
            polygons: [
                Polygon(exterior: square(x: 0, y: 0, size: 100)),
                Polygon(exterior: square(x: 1_000, y: 1_000, size: 200)),
            ]
        )
        #expect(perimeter.contains(point(1_100, 1_100)))
        #expect(!perimeter.contains(point(500, 500)))
        #expect(isClose(perimeter.areaSquareMetres, 50_000, within: 10))
        let box = try #require(perimeter.boundingBox)
        #expect(box.contains(point(600, 600)))
    }
}
