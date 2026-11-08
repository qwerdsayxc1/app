import Foundation
import UserNotifications
import NOVACore

/// Локальные уведомления. Разрешение запрашивается при первом использовании.
@MainActor
final class NotificationService: NotificationPosting {
    func post(title: String, message: String) async throws {
        guard try await Self.ensureAuthorized() else {
            throw AutomationError.notificationsNotAllowed
        }
        try await Self.deliver(title: title, message: message, after: nil)
    }

    /// Отложенное уведомление (таймер). Срабатывает, даже если NOVA свёрнута.
    func schedule(after seconds: TimeInterval, title: String, message: String) async throws {
        guard try await Self.ensureAuthorized() else {
            throw AutomationError.notificationsNotAllowed
        }
        try await Self.deliver(title: title, message: message, after: seconds)
    }

    // nonisolated: объекты UserNotifications создаются и используются в одном контексте,
    // без передачи через границу акторов.
    private nonisolated static func ensureAuthorized() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound])
        default:
            return false
        }
    }

    private nonisolated static func deliver(title: String, message: String, after seconds: TimeInterval?) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        let trigger = seconds.map { UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0), repeats: false) }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }
}
