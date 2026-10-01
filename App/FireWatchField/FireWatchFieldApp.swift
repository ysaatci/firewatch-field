import BackgroundTasks
import SwiftUI

@main
struct FireWatchFieldApp: App {
    nonisolated static let refreshTaskID = "dev.ysaatci.firewatchfield.refresh"

    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()
    @State private var location = LocationProvider()
    @State private var router: Router
    @State private var notifications: NotificationService

    init() {
        let router = Router()
        _router = State(initialValue: router)
        _notifications = State(initialValue: NotificationService(router: router))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(location)
                .environment(router)
                .task {
                    location.start()
                    await model.start()
                }
                .onChange(of: location.coordinate) { _, coordinate in
                    Task { await model.setUserLocation(coordinate) }
                }
                .onChange(of: model.alerts.first) { _, alert in
                    guard let alert else { return }
                    Task {
                        await notifications.requestPermissionIfNeeded()
                        if scenePhase != .active { await notifications.post(alert) }
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Self.scheduleRefresh() }
        }
        .backgroundTask(.appRefresh(Self.refreshTaskID)) { [model, notifications] in
            Self.scheduleRefresh()
            for alert in await model.alertsFromBackgroundRefresh() {
                await notifications.post(alert)
            }
        }
    }

    /// Asks iOS to wake the app in about 15 minutes to check for nearby changes (NFR-5).
    nonisolated private static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
