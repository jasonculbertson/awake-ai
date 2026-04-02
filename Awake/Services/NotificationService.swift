import Foundation
import UserNotifications
import os

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let logger = Logger(subsystem: Constants.appName, category: "Notifications")

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            if let error {
                self.logger.warning("Notification permission: \(error.localizedDescription)")
            } else {
                self.logger.info("Notification permission granted: \(granted)")
            }
        }
    }

    func sendActivated(reasons: [String]) {
        send(
            title: "Awake",
            body: "Keeping awake: \(reasons.joined(separator: ", "))",
            id: "awake-activated"
        )
    }

    func sendDeactivated(reason: String) {
        send(
            title: "Asleep",
            body: "Allowing sleep: \(reason)",
            id: "awake-deactivated"
        )
    }

    private func send(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil
        )

        // Remove the outgoing opposite notification so we never show both
        // "Awake" and "Asleep" banners simultaneously after a rapid transition.
        let oppositeID = id == "awake-activated" ? "awake-deactivated" : "awake-activated"
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [oppositeID])

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.warning("Notification delivery failed: \(error.localizedDescription)")
            }
        }
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }
}
