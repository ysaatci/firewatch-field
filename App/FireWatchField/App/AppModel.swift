import FireWatchClient
import FireWatchCore
import Foundation
import Observation

/// The app's state for SwiftUI: mirrors the ``FieldSession``'s streams onto the main actor.
@MainActor
@Observable
final class AppModel {
    private(set) var field = FieldState.empty
    private(set) var configuration: AppConfiguration
    /// Recent alerts, newest first.
    private(set) var alerts: [HotspotAlert] = []
    /// The alert shown across the top of the app, until dismissed or opened.
    var banner: HotspotAlert?
    /// The latest action the server refused, until dismissed.
    var rejection: FieldSession.Rejection?
    private(set) var isReady = false

    @ObservationIgnored private var session: FieldSession?
    @ObservationIgnored private let container = Storage.makeContainer()
    /// Simulated loss of signal; starts on with the `simulateOutage` default (UI tests).
    @ObservationIgnored let outage = Outage(active: UserDefaults.standard.bool(forKey: "simulateOutage"))
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    /// Kept here so a restarted session still knows where the user is.
    @ObservationIgnored private var userLocation: Coordinate?

    init(configuration: AppConfiguration = .fromDefaults()) {
        self.configuration = configuration
    }

    /// A model frozen at `field`, with no session behind it, for previews and snapshot tests.
    init(previewing field: FieldState) {
        self.configuration = AppConfiguration()
        self.field = field
    }

    /// Starts (or restarts) the session for the current configuration.
    func start() async {
        await stop()
        let session = await AppEnvironment.makeSession(for: configuration, container: container, outage: outage)
        await session.setUserLocation(userLocation)
        await session.start()
        self.session = session
        tasks = [
            Task { [weak self] in
                for await state in session.store.states() { self?.update(state) }
            },
            Task { [weak self] in
                for await alert in session.alerts() { self?.receive(alert) }
            },
            Task { [weak self] in
                for await rejection in session.rejections() { self?.rejection = rejection }
            },
        ]
        isReady = true
    }

    func stop() async {
        for task in tasks { task.cancel() }
        tasks = []
        await session?.stop()
        session = nil
        isReady = false
    }

    /// Switches data source or demo settings, restarting the session.
    func apply(_ configuration: AppConfiguration) async {
        self.configuration = configuration
        field = .empty
        await start()
    }

    func perform(_ action: HotspotAction, on hotspot: Hotspot.ID) async {
        await session?.perform(action, on: hotspot)
    }

    func submit(_ report: SightingReport) async {
        await session?.submit(report)
    }

    func setAlertRadius(_ metres: Double) async {
        configuration.alertRadiusMetres = metres
        await session?.setAlertRadius(metres: metres)
    }

    /// Saves the current state now, so the next launch opens with it.
    func saveCache() async {
        await session?.saveCache()
    }

    func setUserLocation(_ location: Coordinate?) async {
        userLocation = location
        await session?.setUserLocation(location)
    }

    /// Checks the server for alerts while the app is in the background (NFR-5). The live
    /// stream isn't running then, so this fetches one snapshot and compares it with the last
    /// state seen. Demo mode has nothing to fetch.
    func alertsFromBackgroundRefresh() async -> [HotspotAlert] {
        guard case .server(let url, let token) = configuration.source else { return [] }
        let client = APIClient(configuration: .init(baseURL: url, token: token))
        guard let (latest, _) = try? await client.snapshot() else { return [] }
        let engine = AlertEngine(radiusMetres: configuration.alertRadiusMetres)
        return engine.alerts(from: field.fire, to: latest, near: userLocation)
    }

    private func update(_ state: FieldState) {
        // Sent reports leave the queue; their photos aren't needed any more.
        if state.queuedReports != field.queuedReports {
            PhotoStore.prune(keeping: Set(state.queuedReports.compactMap(\.photoFileName)))
        }
        field = state
    }

    private func receive(_ alert: HotspotAlert) {
        alerts.insert(alert, at: 0)
        banner = alert
    }
}
