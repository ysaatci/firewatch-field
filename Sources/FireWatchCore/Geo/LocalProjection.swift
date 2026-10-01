import Foundation

/// Maps coordinates to a flat east/north plane in metres around an origin.
///
/// Uses an equirectangular approximation, which is accurate to well under 1 %
/// over the few-kilometre areas a single fire covers.
public struct LocalProjection: Hashable, Sendable {
    public let origin: Coordinate
    private let metresPerDegreeLatitude: Double
    private let metresPerDegreeLongitude: Double

    public init(origin: Coordinate) {
        self.origin = origin
        metresPerDegreeLatitude = Coordinate.earthRadius * .pi / 180
        metresPerDegreeLongitude = metresPerDegreeLatitude * cos(origin.latitude.radians)
    }

    /// The point `coordinate` as metres east (`x`) and north (`y`) of the origin.
    public func project(_ coordinate: Coordinate) -> PlanarPoint {
        PlanarPoint(
            x: (coordinate.longitude - origin.longitude) * metresPerDegreeLongitude,
            y: (coordinate.latitude - origin.latitude) * metresPerDegreeLatitude
        )
    }

    /// The coordinate `point.x` metres east and `point.y` metres north of the origin.
    public func unproject(_ point: PlanarPoint) -> Coordinate {
        Coordinate(
            latitude: origin.latitude + point.y / metresPerDegreeLatitude,
            longitude: origin.longitude + point.x / metresPerDegreeLongitude
        )
    }
}

/// A point on a local plane, in metres.
public struct PlanarPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
