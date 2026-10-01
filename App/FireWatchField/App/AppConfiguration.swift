import FireWatchSimulator
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

    /// Where settings are stored. The token is in the Keychain, never in user defaults (D11).
    enum Keys {
        static let useServer = "useServer"
        static let serverURL = "serverURL"
        static let serverToken = "serverToken"
        static let demoSpeed = "demoSpeed"
        static let demoStartMinute = "demoStartMinute"
        static let alertRadius = "alertRadiusMetres"
        static let demoPreset = "demoPreset"
    }

    var source: Source = .demo
    /// Scenario seconds per real second in demo mode.
    var demoSpeed: Double = 30
    /// Where the demo starts, so there is something to see at once.
    var demoStartMinute: Double = 60
    /// The simulated fire; `stress` has over 2,000 hotspots for performance tests (NFR-2).
    var demoPreset = ScenarioPreset.default
    var alertRadiusMetres: Double = 2_000

    /// Settings from user defaults and the Keychain. Launch arguments such as
    /// `-demoSpeed 600` override defaults, which UI tests use to run deterministically.
    static func fromDefaults(_ defaults: UserDefaults = .standard) -> AppConfiguration {
        var configuration = AppConfiguration()
        if defaults.bool(forKey: Keys.useServer),
            let text = defaults.string(forKey: Keys.serverURL), let url = URL(string: text), url.scheme != nil
        {
            configuration.source = .server(url: url, token: Keychain.string(for: Keys.serverToken) ?? "")
        }
        if let speed = defaults.number(forKey: Keys.demoSpeed) { configuration.demoSpeed = speed }
        if let minute = defaults.number(forKey: Keys.demoStartMinute) { configuration.demoStartMinute = minute }
        if let radius = defaults.number(forKey: Keys.alertRadius) { configuration.alertRadiusMetres = radius }
        if let name = defaults.string(forKey: Keys.demoPreset), let preset = ScenarioPreset(rawValue: name) {
            configuration.demoPreset = preset
        }
        return configuration
    }
}

extension UserDefaults {
    /// A number stored as a number or as text (launch arguments arrive as text), or `nil` if absent.
    func number(forKey key: String) -> Double? {
        object(forKey: key) == nil ? nil : double(forKey: key)
    }
}
