import FireWatchCore
import UserNotifications

/// Turns alerts into local notifications while the app is in the background, and opens the
/// hotspot when one is tapped (FR-8).
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let router: Router
    private var hasAskedPermission = false

    init(router: Router) {
        self.router = router
        super.init()
        center.delegate = self
    }

    /// Asks once, at the first alert, when the reason is obvious to the user. UI tests skip it
    /// with the `skipNotificationPermission` default, since the prompt would block them.
    func requestPermissionIfNeeded() async {
        guard !hasAskedPermission, !UserDefaults.standard.bool(forKey: "skipNotificationPermission") else { return }
        hasAskedPermission = true
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func post(_ alert: HotspotAlert) async {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.subtitle
        content.sound = .default
        content.userInfo = ["hotspotID": alert.hotspotID.rawValue]
        content.threadIdentifier = "alerts"
        try? await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: nil))
    }

    // MARK: UNUserNotificationCenterDelegate

    /// In the foreground the in-app banner shows the alert instead.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let id = response.notification.request.content.userInfo["hotspotID"] as? String else { return }
        await MainActor.run { router.open(Hotspot.ID(id)) }
    }
}
