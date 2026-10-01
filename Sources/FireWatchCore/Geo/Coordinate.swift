import Foundation

/// A WGS 84 position in degrees.
public struct Coordinate: Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

extension Coordinate {
    /// Mean Earth radius in metres (IUGG).
    public static let earthRadius = 6_371_008.8

    /// Great-circle distance in metres (haversine formula).
    public func distance(to other: Coordinate) -> Double {
        let lat1 = latitude.radians
        let lat2 = other.latitude.radians
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude).radians
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * Self.earthRadius * asin(min(1, sqrt(a)))
    }

    /// Initial bearing towards `other`, in degrees clockwise from true north, in `0..<360`.
    public func bearing(to other: Coordinate) -> Double {
        let lat1 = latitude.radians
        let lat2 = other.latitude.radians
        let dLon = (other.longitude - longitude).radians
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x).degrees.normalizedDegrees
    }
}

extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }

    /// The angle wrapped into `0..<360`.
    var normalizedDegrees: Double {
        let wrapped = truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }
}
