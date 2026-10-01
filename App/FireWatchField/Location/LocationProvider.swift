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

    /// Asks for "when in use" permission if needed, then follows the position.
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
        default: coordinate = nil
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
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
