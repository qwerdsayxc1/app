import AppKit
import ApplicationServices
import NOVACore

/// Работа с окнами через Accessibility API (AXUIElement).
/// Требует разрешения «Универсальный доступ»; без него методы возвращают понятную ошибку.
@MainActor
final class AccessibilityService: WindowManaging {
    private let applications: ApplicationManager

    init(applications: ApplicationManager) {
        self.applications = applications
    }

    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Показывает системный запрос на выдачу доступа (вызывается только по действию пользователя).
    @discardableResult
    func requestTrust() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func focusedWindowTitle(ofApplicationNamed name: String) -> String? {
        guard isAccessibilityTrusted, let app = applications.runningApplication(named: name) else { return nil }
        let element = Self.applicationElement(for: app)
        guard let window = Self.attribute(element, "AXFocusedWindow").map({ $0 as! AXUIElement }) else { return nil }
        return Self.attribute(window, "AXTitle") as? String
    }

    func windowTitles(ofApplicationNamed name: String?) throws -> (application: String, titles: [String]) {
        guard isAccessibilityTrusted else { throw AutomationError.accessibilityNotGranted }
        let app: NSRunningApplication
        if let name {
            guard let found = applications.runningApplication(named: name) else {
                throw AutomationError.applicationNotRunning(name)
            }
            app = found
        } else {
            guard let frontmost = NSWorkspace.shared.frontmostApplication else {
                throw AutomationError.applicationNotRunning("frontmost")
            }
            app = frontmost
        }
        let titles = Self.windows(of: app).compactMap { Self.attribute($0, "AXTitle") as? String }.filter { !$0.isEmpty }
        return (app.localizedName ?? name ?? "?", titles)
    }

    func focusWindow(ofApplicationNamed name: String, titleContaining title: String) throws -> String {
        guard isAccessibilityTrusted else { throw AutomationError.accessibilityNotGranted }
        guard let app = applications.runningApplication(named: name) else {
            throw AutomationError.applicationNotRunning(name)
        }
        for window in Self.windows(of: app) {
            guard let windowTitle = Self.attribute(window, "AXTitle") as? String,
                  windowTitle.localizedCaseInsensitiveContains(title) else { continue }
            if (Self.attribute(window, "AXMinimized") as? Bool) == true {
                AXUIElementSetAttributeValue(window, "AXMinimized" as CFString, kCFBooleanFalse)
            }
            AXUIElementSetAttributeValue(window, "AXMain" as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, "AXRaise" as CFString)
            app.activate()
            return windowTitle
        }
        throw AutomationError.windowNotFound(application: app.localizedName ?? name, title: title)
    }

    func performWindowAction(_ action: WindowAction, ofApplicationNamed name: String?) throws -> String {
        guard isAccessibilityTrusted else { throw AutomationError.accessibilityNotGranted }
        let app: NSRunningApplication
        if let name {
            guard let found = applications.runningApplication(named: name) else {
                throw AutomationError.applicationNotRunning(name)
            }
            app = found
        } else {
            guard let frontmost = NSWorkspace.shared.frontmostApplication else {
                throw AutomationError.applicationNotRunning("frontmost")
            }
            app = frontmost
        }
        let appName = app.localizedName ?? name ?? "?"
        let element = Self.applicationElement(for: app)
        let windows = Self.windows(of: app)

        switch action {
        case .restore:
            guard let minimized = windows.first(where: { (Self.attribute($0, "AXMinimized") as? Bool) == true }) else {
                throw AutomationError.noWindow(appName)
            }
            AXUIElementSetAttributeValue(minimized, "AXMinimized" as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(minimized, "AXRaise" as CFString)
            app.activate()
        case .minimize, .fullscreen, .exitFullscreen:
            let focused = Self.attribute(element, "AXFocusedWindow").map { $0 as! AXUIElement } ?? windows.first
            guard let window = focused else { throw AutomationError.noWindow(appName) }
            switch action {
            case .minimize:
                AXUIElementSetAttributeValue(window, "AXMinimized" as CFString, kCFBooleanTrue)
            case .fullscreen:
                AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanTrue)
            default:
                AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse)
            }
        }
        return appName
    }

    // MARK: - AX helpers

    private static func applicationElement(for app: NSRunningApplication) -> AXUIElement {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // Зависшее приложение не должно блокировать NOVA.
        AXUIElementSetMessagingTimeout(element, 1.0)
        return element
    }

    private static func windows(of app: NSRunningApplication) -> [AXUIElement] {
        let element = applicationElement(for: app)
        return attribute(element, "AXWindows") as? [AXUIElement] ?? []
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return result == .success ? value : nil
    }
}
