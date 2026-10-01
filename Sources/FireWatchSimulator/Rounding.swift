import FireWatchCore
import Foundation

extension Double {
    /// The value rounded to `places` decimal places, to keep simulated output free of float noise.
    func rounded(toPlaces places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}

extension TerrainGrid {
    /// The coordinate of `point` (metres from the grid centre), at GPS precision:
    /// 7 decimal places, about 1 cm.
    public func coordinate(at point: PlanarPoint) -> Coordinate {
        let coordinate = projection.unproject(point)
        return Coordinate(
            latitude: coordinate.latitude.rounded(toPlaces: 7),
            longitude: coordinate.longitude.rounded(toPlaces: 7)
        )
    }
}
