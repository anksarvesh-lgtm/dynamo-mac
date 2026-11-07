// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import UserNotifications

/**
 * Manages native macOS call notification banners and interactive response actions.
 */
public final class CallNotifier: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = CallNotifier()

    public typealias ActionHandler = (String, String) -> Void
    public var onAction: ActionHandler?

    public static let categoryRinging = "CALL_RINGING"
    public static let categoryActive = "CALL_ACTIVE"

    public static let actionAnswer = "answer"
    public static let actionDecline = "decline"
    public static let actionEnd = "end"

    private override init() {
        super.init()
        if Bundle.main.bundleIdentifier != nil {
            registerCategories()
        }
    }

    public func registerCategories() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()

        let answerAction = UNNotificationAction(
            identifier: Self.actionAnswer,
            title: "Answer",
            options: [.foreground]
        )
        let declineAction = UNNotificationAction(
            identifier: Self.actionDecline,
            title: "Decline",
            options: [.destructive]
        )
        let endAction = UNNotificationAction(
            identifier: Self.actionEnd,
            title: "End Call",
            options: [.destructive]
        )

        let ringingCategory = UNNotificationCategory(
            identifier: Self.categoryRinging,
            actions: [answerAction, declineAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let activeCategory = UNNotificationCategory(
            identifier: Self.categoryActive,
            actions: [endAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([ringingCategory, activeCategory])
        center.delegate = self
    }

    public func showRinging(callId: String, callerName: String?, callerNumber: String?) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        let displayName = callerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = callerNumber?.trimmingCharacters(in: .whitespacesAndNewlines)

        content.title = displayName?.isEmpty == false ? displayName! : (number?.isEmpty == false ? number! : "Incoming Call")
        if let name = displayName, !name.isEmpty, let num = number, !num.isEmpty {
            content.subtitle = num
        }
        content.body = "Phone Call"
        content.categoryIdentifier = Self.categoryRinging
        content.sound = UNNotificationSound.default
        content.userInfo = ["callId": callId]

        let request = UNNotificationRequest(identifier: "call_\(callId)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    public func showActive(callId: String, callerName: String?, callerNumber: String?) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        let displayName = callerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = callerNumber?.trimmingCharacters(in: .whitespacesAndNewlines)

        content.title = displayName?.isEmpty == false ? displayName! : (number?.isEmpty == false ? number! : "Active Call")
        if let name = displayName, !name.isEmpty, let num = number, !num.isEmpty {
            content.subtitle = num
        }
        content.body = "Call in progress"
        content.categoryIdentifier = Self.categoryActive
        content.sound = nil
        content.userInfo = ["callId": callId]

        let request = UNNotificationRequest(identifier: "call_\(callId)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    public func dismiss(callId: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["call_\(callId)"])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["call_\(callId)"])
    }

    // MARK: - UNUserNotificationCenterDelegate

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let callId = (response.notification.request.content.userInfo["callId"] as? String)
            ?? response.notification.request.identifier.replacingOccurrences(of: "call_", with: "")

        let actionId = response.actionIdentifier
        if actionId == Self.actionAnswer || actionId == Self.actionDecline || actionId == Self.actionEnd {
            onAction?(callId, actionId)
        } else if actionId == UNNotificationDefaultActionIdentifier {
            onAction?(callId, "opened")
        } else if actionId == UNNotificationDismissActionIdentifier {
            onAction?(callId, "dismissed")
        }
        completionHandler()
    }
}

