import FireWatchCore
import Foundation

/// Whether two values are within `tolerance` of each other.
public func isClose(_ a: Double, _ b: Double, within tolerance: Double) -> Bool {
    abs(a - b) <= tolerance
}

extension Coordinate {
    public static let london = Coordinate(latitude: 51.5074, longitude: -0.1278)
    public static let paris = Coordinate(latitude: 48.8566, longitude: 2.3522)
    public static let manavgat = Coordinate(latitude: 36.787, longitude: 31.443)
}

extension URL {
    /// A URL from a literal known to be valid; crashes the test run on a typo.
    public init(_ literal: StaticString) {
        guard let url = URL(string: "\(literal)") else { preconditionFailure("Invalid URL literal \(literal)") }
        self = url
    }
}
