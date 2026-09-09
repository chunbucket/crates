import AppKit
import UserNotifications

/// System notifications for records that finish while the shelf is put away.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    /// Tapping a notification.
    var onActivate: (() -> Void)?

    /// UNUserNotificationCenter aborts the process outside a real .app bundle
    /// (plain `swift run`), so everything is a no-op there.
    private let available = Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")

    func start() {
        guard available else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    func post(title: String, body: String) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        // Returns the current status without re-prompting once the user has answered.
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { self.onActivate?() }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
