import FireWatchCore
import Observation

/// Where the user is in the app, so alerts and notifications can take them to a hotspot.
@MainActor
@Observable
final class Router {
    var tab = RootView.Section.map
    /// The hotspot list's navigation stack.
    var hotspotPath: [Hotspot.ID] = []

    /// Shows a hotspot's detail screen from anywhere.
    func open(_ hotspot: Hotspot.ID) {
        tab = .hotspots
        hotspotPath = [hotspot]
    }
}
