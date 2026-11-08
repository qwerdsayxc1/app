import AppKit
import NOVACore

/// Управление приложениями: запуск, закрытие, переключение, список запущенных.
@MainActor
final class ApplicationManager: ApplicationManaging {
    private let resolver = AppAliasResolver()
    private let workspace = NSWorkspace.shared

    /// Где искать .app, если приложения нет в таблице алиасов.
    private var searchDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            home.appendingPathComponent("Applications"),
            home.appendingPathComponent("Applications/JetBrains Toolbox")
        ]
    }

    // MARK: ApplicationManaging

    func openApplication(named name: String) async throws -> String {
        guard let url = applicationURL(named: name) else {
            throw AutomationError.applicationNotFound(name)
        }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle(url: url)?.bundleIdentifier ?? "").first {
            running.unhide()
            running.activate()
            return running.localizedName ?? name
        }
        return try await WorkspaceLauncher.launchApplication(at: url)
    }

    func quitApplication(named name: String) throws -> String {
        guard let app = runningApplication(named: name) else {
            throw AutomationError.applicationNotRunning(name)
        }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            throw AutomationError.scriptFailed("NOVA cannot quit itself by voice command.")
        }
        // Только мягкое завершение: приложение само спросит про несохранённые документы.
        guard app.terminate() else {
            throw AutomationError.scriptFailed("\(app.localizedName ?? name) refused to quit.")
        }
        return app.localizedName ?? name
    }

    func switchToApplication(named name: String) throws -> String {
        guard let app = runningApplication(named: name) else {
            throw AutomationError.applicationNotRunning(name)
        }
        app.unhide()
        app.activate()
        return app.localizedName ?? name
    }

    func runningApplicationNames() -> [String] {
        var seen = Set<String>()
        return workspace.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName)
            .filter { seen.insert($0).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func frontmostApplicationName() -> String? {
        workspace.frontmostApplication?.localizedName
    }

    // MARK: Поиск

    /// Запущенное приложение по произнесённому имени (алиас → bundle id, затем по названию).
    func runningApplication(named name: String) -> NSRunningApplication? {
        let regular = workspace.runningApplications.filter { $0.activationPolicy == .regular }
        if let known = resolver.resolve(name) {
            if let app = regular.first(where: { known.bundleIdentifiers.contains($0.bundleIdentifier ?? "") }) {
                return app
            }
        }
        let canonical = resolver.resolve(name)?.canonicalName ?? name
        return regular
            .map { app in (app, max(
                AppAliasResolver.matchScore(query: name, candidate: app.localizedName ?? ""),
                AppAliasResolver.matchScore(query: canonical, candidate: app.localizedName ?? "")
            )) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// URL установленного приложения: таблица алиасов → поиск по каталогам приложений.
    func applicationURL(named name: String) -> URL? {
        let known = resolver.resolve(name)
        if let known, let url = WorkspaceLauncher.applicationURL(bundleIdentifiers: known.bundleIdentifiers) {
            return url
        }
        let queries = [name, known?.canonicalName].compactMap { $0 }
        var best: (url: URL, score: Int)?
        for directory in searchDirectories {
            guard let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for item in items where item.pathExtension == "app" {
                let appName = item.deletingPathExtension().lastPathComponent
                let score = queries.map { AppAliasResolver.matchScore(query: $0, candidate: appName) }.max() ?? 0
                if score > (best?.score ?? 0) {
                    best = (item, score)
                }
            }
        }
        return best?.url
    }
}
