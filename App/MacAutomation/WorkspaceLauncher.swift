import AppKit
import NOVACore

/// Обёртки над NSWorkspace с completion-handler'ами.
///
/// Функции nonisolated и статические: замыкания, которые NSWorkspace вызывает на своей очереди,
/// не должны быть изолированы на MainActor (в Swift 6 это приводит к падению по проверке очереди).
/// Наружу возвращаются только Sendable-значения (String), а не NSRunningApplication.
enum WorkspaceLauncher {
    /// Запускает приложение и возвращает его отображаемое имя.
    static func launchApplication(at url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
                if let error {
                    continuation.resume(throwing: AutomationError.launchFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: app?.localizedName ?? url.deletingPathExtension().lastPathComponent)
                }
            }
        }
    }

    /// Открывает URL/файлы в конкретном приложении.
    static func open(_ urls: [URL], withApplicationAt applicationURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open(urls, withApplicationAt: applicationURL, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: AutomationError.launchFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// URL приложения по первому установленному bundle id из списка.
    static func applicationURL(bundleIdentifiers: [String]) -> URL? {
        for identifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return url
            }
        }
        return nil
    }
}
