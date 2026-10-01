import CoreLocation
import FireWatchCore
import Observation

/// The user's position while the app is in use (NFR-5, NFR-8): never in the background.
@MainActor
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var coordinate: Coordinate?
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
    }

    /// Asks for "when in use" permission if needed, then follows the position. A `fixedLocation`
    /// default of "latitude,longitude" replaces the real position, so UI tests don't depend on
    /// the simulator's location services.
    func start() {
        if let fixed = Self.fixedLocation {
            coordinate = fixed
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
        default: coordinate = nil
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    private static var fixedLocation: Coordinate? {
        let parts = UserDefaults.standard.string(forKey: "fixedLocation")?.split(separator: ",").compactMap {
            Double($0.trimmingCharacters(in: .whitespaces))
        }
        guard let parts, parts.count == 2 else { return nil }
        return Coordinate(latitude: parts[0], longitude: parts[1])
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.start() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let coordinate = Coordinate(latest.coordinate)
        Task { @MainActor in self.coordinate = coordinate }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // Keep the last known position; the manager keeps trying.
    }
}
