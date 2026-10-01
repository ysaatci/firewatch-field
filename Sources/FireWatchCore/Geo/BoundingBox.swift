/// A latitude/longitude-aligned rectangle. Does not handle the antimeridian,
/// which no fire in scope crosses.
public struct BoundingBox: Hashable, Sendable {
    public var southWest: Coordinate
    public var northEast: Coordinate

    public init(southWest: Coordinate, northEast: Coordinate) {
        self.southWest = southWest
        self.northEast = northEast
    }

    /// The smallest box containing every coordinate, or `nil` when there are none.
    public init?(enclosing coordinates: some Sequence<Coordinate>) {
        var iterator = coordinates.makeIterator()
        guard let first = iterator.next() else { return nil }
        var box = BoundingBox(southWest: first, northEast: first)
        while let next = iterator.next() { box.include(next) }
        self = box
    }

    public var center: Coordinate {
        Coordinate(
            latitude: (southWest.latitude + northEast.latitude) / 2,
            longitude: (southWest.longitude + northEast.longitude) / 2
        )
    }

    public func contains(_ coordinate: Coordinate) -> Bool {
        (southWest.latitude...northEast.latitude).contains(coordinate.latitude)
            && (southWest.longitude...northEast.longitude).contains(coordinate.longitude)
    }

    /// Grows the box, if needed, so it contains `coordinate`.
    public mutating func include(_ coordinate: Coordinate) {
        southWest.latitude = min(southWest.latitude, coordinate.latitude)
        southWest.longitude = min(southWest.longitude, coordinate.longitude)
        northEast.latitude = max(northEast.latitude, coordinate.latitude)
        northEast.longitude = max(northEast.longitude, coordinate.longitude)
    }

    /// The box grown by `metres` on every side.
    public func expanded(byMetres metres: Double) -> BoundingBox {
        let projection = LocalProjection(origin: center)
        let sw = projection.project(southWest)
        let ne = projection.project(northEast)
        return BoundingBox(
            southWest: projection.unproject(PlanarPoint(x: sw.x - metres, y: sw.y - metres)),
            northEast: projection.unproject(PlanarPoint(x: ne.x + metres, y: ne.y + metres))
        )
    }
}
