import Foundation

/// The burned or burning area at a moment in time. Spot fires make it a set of
/// polygons rather than one.
public struct FirePerimeter: Hashable, Sendable {
    public var time: Date
    public var polygons: [Polygon]

    public init(time: Date, polygons: [Polygon]) {
        self.time = time
        self.polygons = polygons
    }

    public func contains(_ coordinate: Coordinate) -> Bool {
        polygons.contains { $0.contains(coordinate) }
    }

    public var areaSquareMetres: Double {
        polygons.reduce(0) { $0 + $1.areaSquareMetres }
    }

    public var boundingBox: BoundingBox? {
        BoundingBox(enclosing: polygons.lazy.flatMap(\.exterior))
    }
}

/// A polygon with optional holes (unburned islands). Rings are stored open:
/// the last vertex is not a repeat of the first.
public struct Polygon: Hashable, Sendable {
    public var exterior: [Coordinate]
    public var holes: [[Coordinate]]

    public init(exterior: [Coordinate], holes: [[Coordinate]] = []) {
        self.exterior = exterior
        self.holes = holes
    }

    public func contains(_ coordinate: Coordinate) -> Bool {
        Self.ring(exterior, contains: coordinate) && !holes.contains { Self.ring($0, contains: coordinate) }
    }

    public var areaSquareMetres: Double {
        guard let origin = exterior.first else { return 0 }
        let projection = LocalProjection(origin: origin)
        return holes.reduce(Self.area(of: exterior, in: projection)) {
            $0 - Self.area(of: $1, in: projection)
        }
    }

    /// Even-odd ray casting. Treating degrees as planar is fine at fire scale.
    private static func ring(_ ring: [Coordinate], contains point: Coordinate) -> Bool {
        var inside = false
        var previous = ring.last
        for vertex in ring {
            defer { previous = vertex }
            guard let previous else { continue }
            let crossesLatitude = (vertex.latitude > point.latitude) != (previous.latitude > point.latitude)
            guard crossesLatitude else { continue }
            let crossingLongitude =
                vertex.longitude + (point.latitude - vertex.latitude) / (previous.latitude - vertex.latitude)
                * (previous.longitude - vertex.longitude)
            if point.longitude < crossingLongitude { inside.toggle() }
        }
        return inside
    }

    /// Shoelace formula on the projected ring.
    private static func area(of ring: [Coordinate], in projection: LocalProjection) -> Double {
        let points = ring.map(projection.project)
        guard points.count >= 3 else { return 0 }
        var twiceArea = 0.0
        for (index, point) in points.enumerated() {
            let next = points[(index + 1) % points.count]
            twiceArea += point.x * next.y - next.x * point.y
        }
        return abs(twiceArea) / 2
    }
}
