import Foundation
import NOVACore

/// Таймеры (локальные уведомления) и напоминания (приложение «Напоминания»).
@MainActor
final class ProductivityService: ProductivityManaging {
    private let notifications: NotificationService

    init(notifications: NotificationService) {
        self.notifications = notifications
    }

    func scheduleTimer(minutes: Int, label: String) async throws -> Date {
        let seconds = TimeInterval(min(max(minutes, 1), 1440) * 60)
        try await notifications.schedule(after: seconds, title: "NOVA ⏱", message: label)
        return Date().addingTimeInterval(seconds)
    }

    /// Текст передаётся аргументом osascript, в исходник скрипта не подставляется.
    /// macOS один раз спросит разрешение на управление «Напоминаниями».
    func createReminder(title: String) async throws {
        _ = try await AppleScriptRunner.run(AppleScriptRunner.Script.createReminder, arguments: [title])
    }
}
