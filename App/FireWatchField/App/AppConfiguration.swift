import Foundation

/// Where the app gets its data, and how the demo runs.
struct AppConfiguration: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        /// The simulator runs on the device (FR-11). The default.
        case demo
        /// The simulator server, or later the real backend.
        case server(url: URL, token: String)

        /// Keeps each source's cache and queue apart, so demo actions never reach a server.
        var storageKey: String {
            switch self {
            case .demo: "demo"
            case .server(let url, _): "server:\(url.absoluteString)"
            }
        }
    }

    var source: Source = .demo
    /// Scenario seconds per real second in demo mode.
    var demoSpeed: Double = 30
    /// Where the demo starts, so there is something to see at once.
    var demoStartMinute: Double = 60
    var alertRadiusMetres: Double = 2_000

    /// Settings from user defaults, which launch arguments such as `-demoSpeed 600` override.
    /// UI tests use that to run the demo fast and deterministically.
    static func fromDefaults(_ defaults: UserDefaults = .standard) -> AppConfiguration {
        var configuration = AppConfiguration()
        if let speed = defaults.object(forKey: "demoSpeed") as? Double { configuration.demoSpeed = speed }
        if let minute = defaults.object(forKey: "demoStartMinute") as? Double {
            configuration.demoStartMinute = minute
        }
        if let radius = defaults.object(forKey: "alertRadiusMetres") as? Double {
            configuration.alertRadiusMetres = radius
        }
        return configuration
    }
}
