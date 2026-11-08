import AppKit
import UserNotifications
import NOVACore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var floatingPanel: FloatingPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment.shared

        // Push-to-talk: удерживайте ⌥Space — говорите — отпустите.
        let hotkeys = HotkeyManager.shared
        hotkeys.onPress = { environment.assistant.hotkeyPressed() }
        hotkeys.onRelease = { environment.assistant.hotkeyReleased() }
        hotkeys.register()

        UNUserNotificationCenter.current().delegate = self

        if environment.settings.settings.showFloatingPanelOnLaunch {
            toggleFloatingPanel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
        AppEnvironment.shared.assistant.interrupt()
    }

    /// Приложение продолжает работать из строки меню после закрытия главного окна.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func toggleFloatingPanel() {
        if floatingPanel == nil {
            let environment = AppEnvironment.shared
            floatingPanel = FloatingPanelController(assistant: environment.assistant, settings: environment.settings)
        }
        floatingPanel?.toggle()
    }

    // Показывать уведомления NOVA, даже когда приложение активно.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
