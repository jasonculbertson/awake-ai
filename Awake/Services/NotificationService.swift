import Foundation
import UserNotifications
import os

// Notification posted when user taps "Stop Session" from a reminder notification
extension Notification.Name {
    static let stopSessionFromNotification = Notification.Name("stopSessionFromNotification")
    static let keepAwakeFromNotification = Notification.Name("keepAwakeFromNotification")
}

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let logger = Logger(subsystem: Constants.appName, category: "Notifications")

    // Notification category and action identifiers
    private let sessionReminderCategoryID = "session-reminder"
    private let workCompleteCategoryID = "work-complete"
    private let stopSessionActionID = "stop-session"
    private let keepAwakeActionID = "keep-awake"

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
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

    // MARK: - Category Registration

    private func registerCategories() {
        let stopAction = UNNotificationAction(
            identifier: stopSessionActionID,
            title: "Stop Session",
            options: [.destructive]
        )
        let keepAwakeAction = UNNotificationAction(
            identifier: keepAwakeActionID,
            title: "Keep Awake",
            options: []
        )

        let reminderCategory = UNNotificationCategory(
            identifier: sessionReminderCategoryID,
            actions: [stopAction, keepAwakeAction],
            intentIdentifiers: [],
            options: []
        )

        let workCompleteCategory = UNNotificationCategory(
            identifier: workCompleteCategoryID,
            actions: [keepAwakeAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([reminderCategory, workCompleteCategory])
    }

    // MARK: - Standard Notifications

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

    // MARK: - Session Reminder

    /// Schedule a future reminder that fires after the given interval.
    func scheduleSessionReminder(after interval: TimeInterval) {
        cancelSessionReminder()

        let content = UNMutableNotificationContent()
        content.title = "Still Awake"
        content.body = "Awake has been keeping your Mac awake. Tap to stop or keep going."
        content.categoryIdentifier = sessionReminderCategoryID

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: "session-reminder",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.warning("Session reminder scheduling failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelSessionReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["session-reminder"])
    }

    // MARK: - Work Complete Notification

    func sendWorkCompleted(appName: String, reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(appName) finished"
        content.body = "\(reason) — Awake turned off automatically."
        content.categoryIdentifier = workCompleteCategoryID

        let request = UNNotificationRequest(
            identifier: "work-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                self?.logger.warning("Work complete notification failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

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

    // MARK: - UNUserNotificationCenterDelegate

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    // Handle action button taps
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case stopSessionActionID:
            NotificationCenter.default.post(name: .stopSessionFromNotification, object: nil)
        case keepAwakeActionID:
            NotificationCenter.default.post(name: .keepAwakeFromNotification, object: nil)
        default:
            break
        }
        completionHandler()
    }
}
