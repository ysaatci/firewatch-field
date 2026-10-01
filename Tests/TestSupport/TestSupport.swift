import FireWatchCore

/// Whether two values are within `tolerance` of each other.
public func isClose(_ a: Double, _ b: Double, within tolerance: Double) -> Bool {
    abs(a - b) <= tolerance
}

extension Coordinate {
    public static let london = Coordinate(latitude: 51.5074, longitude: -0.1278)
    public static let paris = Coordinate(latitude: 48.8566, longitude: 2.3522)
    public static let manavgat = Coordinate(latitude: 36.787, longitude: 31.443)
}
