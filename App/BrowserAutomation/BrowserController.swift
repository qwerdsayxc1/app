import AppKit
import NOVACore

/// Открытие веб-страниц в Safari, Chrome или браузере по умолчанию.
/// Принимает только http(s)-URL — проверка дублирует валидатор инструментов (defense in depth).
@MainActor
final class BrowserController: BrowserControlling {
    static let safariBundleID = "com.apple.Safari"
    static let chromeBundleID = "com.google.Chrome"

    func open(_ url: URL, in browser: BrowserChoice) async throws {
        guard let safeURL = WebURLBuilder.validatedWebURL(url.absoluteString) else {
            throw ToolValidationError.invalidURL(argument: "url")
        }
        switch browser {
        case .systemDefault:
            guard NSWorkspace.shared.open(safeURL) else {
                throw AutomationError.launchFailed("No default browser could open \(safeURL.host ?? "URL").")
            }
        case .safari:
            try await open(safeURL, bundleID: Self.safariBundleID, displayName: "Safari")
        case .chrome:
            try await open(safeURL, bundleID: Self.chromeBundleID, displayName: "Google Chrome")
        }
    }

    private func open(_ url: URL, bundleID: String, displayName: String) async throws {
        guard let browserURL = WorkspaceLauncher.applicationURL(bundleIdentifiers: [bundleID]) else {
            throw AutomationError.browserNotInstalled(displayName)
        }
        try await WorkspaceLauncher.open([url], withApplicationAt: browserURL)
    }
}
