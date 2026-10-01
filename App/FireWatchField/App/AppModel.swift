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
    private(set) var alerts: [Alert] = []
    /// The latest action the server refused, until dismissed.
    var rejection: FieldSession.Rejection?
    private(set) var isReady = false

    @ObservationIgnored private var session: FieldSession?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    init(configuration: AppConfiguration = .fromDefaults()) {
        self.configuration = configuration
    }

    /// Starts (or restarts) the session for the current configuration.
    func start() async {
        await stop()
        let session = await AppEnvironment.makeSession(for: configuration)
        await session.start()
        self.session = session
        tasks = [
            Task { [weak self] in
                for await state in session.store.states() { self?.field = state }
            },
            Task { [weak self] in
                for await alert in session.alerts() { self?.alerts.insert(alert, at: 0) }
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

    func setUserLocation(_ location: Coordinate?) async {
        await session?.setUserLocation(location)
    }
}
