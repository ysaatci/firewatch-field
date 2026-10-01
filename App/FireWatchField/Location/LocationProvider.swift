import CoreLocation
import FireWatchCore
import Observation

/// The user's position while the app is in use (NFR-5, NFR-8): never in the background.
@MainActor
@Observable
final class LocationProvider {
    private(set) var coordinate: Coordinate?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var updates: Task<Void, Never>?

    /// Asks for "when in use" permission if needed, then follows the position until ``stop()``.
    /// Off when the `disableLocation` default is set, which UI tests use to avoid the prompt.
    func start() {
        guard updates == nil, !UserDefaults.standard.bool(forKey: "disableLocation") else { return }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        updates = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if let location = update.location {
                        self?.coordinate = Coordinate(location.coordinate)
                    }
                }
            } catch {
                self?.coordinate = nil
            }
        }
    }

    func stop() {
        updates?.cancel()
        updates = nil
    }
}
