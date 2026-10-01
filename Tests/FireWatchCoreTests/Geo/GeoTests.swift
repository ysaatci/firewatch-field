import Testing

@testable import FireWatchCore

struct CoordinateTests {
    @Test func distanceLondonToParis() {
        // Reference: 343.5 km great-circle distance.
        #expect(isClose(Coordinate.london.distance(to: .paris), 343_560, within: 500))
    }

    @Test func distanceIsSymmetricAndZeroToSelf() {
        #expect(Coordinate.london.distance(to: .london) == 0)
        let there = Coordinate.london.distance(to: .paris)
        let back = Coordinate.paris.distance(to: .london)
        #expect(isClose(there, back, within: 1e-6))
    }

    @Test func bearingLondonToParis() {
        // Reference: initial bearing 148.1°.
        #expect(isClose(Coordinate.london.bearing(to: .paris), 148.1, within: 0.2))
    }

    @Test(arguments: [
        (Coordinate(latitude: 1, longitude: 0), 0.0),
        (Coordinate(latitude: 0, longitude: 1), 90.0),
        (Coordinate(latitude: -1, longitude: 0), 180.0),
        (Coordinate(latitude: 0, longitude: -1), 270.0),
    ])
    func bearingCardinalDirections(target: Coordinate, expected: Double) {
        let origin = Coordinate(latitude: 0, longitude: 0)
        #expect(isClose(origin.bearing(to: target), expected, within: 1e-9))
    }

    @Test func normalizedDegreesWrapsIntoRange() {
        #expect((-90.0).normalizedDegrees == 270)
        #expect(720.5.normalizedDegrees == 0.5)
    }
}

struct LocalProjectionTests {
    @Test func roundTripsPoints() {
        let projection = LocalProjection(origin: .manavgat)
        let point = PlanarPoint(x: 1_234, y: -2_345)
        let back = projection.project(projection.unproject(point))
        #expect(isClose(back.x, point.x, within: 1e-6))
        #expect(isClose(back.y, point.y, within: 1e-6))
    }

    @Test func planarDistanceMatchesHaversineAtFireScale() {
        let projection = LocalProjection(origin: .manavgat)
        let target = projection.unproject(PlanarPoint(x: 3_000, y: 4_000))
        #expect(isClose(Coordinate.manavgat.distance(to: target), 5_000, within: 5))
    }
}

struct BoundingBoxTests {
    @Test func enclosingCoordinates() throws {
        let box = try #require(BoundingBox(enclosing: [Coordinate.london, .paris, .manavgat]))
        #expect(box.southWest == Coordinate(latitude: 36.787, longitude: -0.1278))
        #expect(box.northEast == Coordinate(latitude: 51.5074, longitude: 31.443))
        #expect(box.contains(.paris))
        #expect(!box.contains(Coordinate(latitude: 60, longitude: 0)))
    }

    @Test func enclosingNothingIsNil() {
        #expect(BoundingBox(enclosing: [Coordinate]()) == nil)
    }

    @Test func expandedGrowsEverySide() {
        let box = BoundingBox(southWest: .manavgat, northEast: .manavgat).expanded(byMetres: 1_000)
        #expect(isClose(box.southWest.distance(to: .manavgat), 1_414, within: 5))
        #expect(isClose(box.northEast.distance(to: .manavgat), 1_414, within: 5))
    }
}
