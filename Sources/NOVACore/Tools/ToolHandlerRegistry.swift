import Foundation

/// Зависимости обработчиков инструментов.
@MainActor
public struct ToolServices {
    public let applications: ApplicationManaging
    public let browser: BrowserControlling
    public let system: SystemManaging
    public let notifications: NotificationPosting
    public let windows: WindowManaging
    public let projects: ProjectOpening
    public let settings: () -> AppSettings

    public init(
        applications: ApplicationManaging,
        browser: BrowserControlling,
        system: SystemManaging,
        notifications: NotificationPosting,
        windows: WindowManaging,
        projects: ProjectOpening,
        settings: @escaping () -> AppSettings
    ) {
        self.applications = applications
        self.browser = browser
        self.system = system
        self.notifications = notifications
        self.windows = windows
        self.projects = projects
        self.settings = settings
    }
}

/// Связывает каждый инструмент белого списка с его реализацией.
/// Результаты возвращаются модели компактным JSON — дальше она сама формулирует ответ
/// на языке пользователя.
@MainActor
public enum ToolHandlerRegistry {
    public static func makeHandlers(_ services: ToolServices) -> [ToolName: ToolHandler] {
        var handlers: [ToolName: ToolHandler] = [:]
        for name in ToolName.allCases {
            handlers[name] = handler(for: name, services: services)
        }
        return handlers
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func handler(for name: ToolName, services: ToolServices) -> ToolHandler {
        switch name {
        // MARK: Приложения
        case .openApplication:
            return { args in
                let opened = try await services.applications.openApplication(named: try args.requiredString("name"))
                return json(["status": "opened", "application": .string(opened)])
            }
        case .quitApplication:
            return { args in
                let quit = try services.applications.quitApplication(named: try args.requiredString("name"))
                return json(["status": "quit_requested", "application": .string(quit)])
            }
        case .switchToApplication:
            return { args in
                let active = try services.applications.switchToApplication(named: try args.requiredString("name"))
                return json(["status": "activated", "application": .string(active)])
            }
        case .listRunningApplications:
            return { _ in
                let names = services.applications.runningApplicationNames()
                return json(["applications": .array(names.map(JSONValue.string)), "count": .number(Double(names.count))])
            }

        // MARK: Браузер
        case .openURL:
            return { args in
                guard let url = WebURLBuilder.validatedWebURL(try args.requiredString("url")) else {
                    throw ToolValidationError.invalidURL(argument: "url")
                }
                let browser = resolveBrowser(args.string("browser"), settings: services.settings())
                try await services.browser.open(url, in: browser)
                return json(["status": "opened", "url": .string(url.absoluteString), "browser": .string(browser.rawValue)])
            }
        case .openWebsite:
            return { args in
                let site = try args.requiredString("site")
                guard let url = WebURLBuilder.websiteURL(for: site) else {
                    throw ToolValidationError.valueNotAllowed(argument: "site", value: site, allowed: ToolCatalog.knownWebsites)
                }
                let browser = resolveBrowser(args.string("browser"), settings: services.settings())
                try await services.browser.open(url, in: browser)
                return json(["status": "opened", "url": .string(url.absoluteString), "browser": .string(browser.rawValue)])
            }
        case .webSearch:
            return { args in
                let engine = try args.requiredString("engine")
                let query = try args.requiredString("query")
                guard let url = WebURLBuilder.searchURL(engine: engine, query: query) else {
                    throw ToolValidationError.valueNotAllowed(argument: "engine", value: engine, allowed: ToolCatalog.searchEngines)
                }
                let browser = resolveBrowser(args.string("browser"), settings: services.settings())
                try await services.browser.open(url, in: browser)
                return json(["status": "opened_search_results", "engine": .string(engine), "query": .string(query), "url": .string(url.absoluteString)])
            }

        // MARK: Система
        case .getVolume:
            return { _ in
                let state = try await services.system.volume()
                return json(["volume_percent": .number(Double(state.level)), "muted": .bool(state.isMuted)])
            }
        case .setVolume:
            return { args in
                let level = try args.requiredInt("level")
                try await services.system.setVolume(level)
                if level > 0 { try await services.system.setMuted(false) }
                return json(["volume_percent": .number(Double(level))])
            }
        case .changeVolume:
            return { args in
                let delta = try args.requiredInt("delta")
                let current = try await services.system.volume()
                let target = VolumeMath.apply(delta: delta, to: current.level)
                try await services.system.setVolume(target)
                // «Сделай громче» при выключенном звуке логично включает звук.
                if delta > 0, current.isMuted { try await services.system.setMuted(false) }
                return json([
                    "previous_percent": .number(Double(current.level)),
                    "volume_percent": .number(Double(target)),
                    "clamped": .bool(target != current.level + delta)
                ])
            }
        case .setMute:
            return { args in
                let muted = try args.requiredBool("muted")
                try await services.system.setMuted(muted)
                return json(["muted": .bool(muted)])
            }
        case .getBatteryStatus:
            return { _ in
                let battery = try services.system.batteryStatus()
                var result: [String: JSONValue] = [
                    "percent": .number(Double(battery.percent)),
                    "charging": .bool(battery.isCharging),
                    "on_ac_power": .bool(battery.isOnACPower)
                ]
                if let minutes = battery.minutesRemaining { result["minutes_remaining"] = .number(Double(minutes)) }
                return json(result)
            }
        case .getDiskSpace:
            return { _ in
                let disk = try services.system.diskSpace()
                return json([
                    "available_gb": .number(ByteMath.gigabytes(disk.availableBytes)),
                    "total_gb": .number(ByteMath.gigabytes(disk.totalBytes)),
                    "used_percent": .number(ByteMath.usedPercent(available: disk.availableBytes, total: disk.totalBytes))
                ])
            }
        case .getSystemInfo:
            return { _ in
                let info = services.system.systemInfo()
                return json([
                    "macos": .string(info.osVersion),
                    "model": .string(info.modelIdentifier),
                    "chip": .string(info.chip),
                    "memory_gb": .number(ByteMath.gigabytes(Int64(clamping: info.memoryBytes))),
                    "cpu_cores": .number(Double(info.cpuCores)),
                    "uptime_hours": .number((info.uptimeSeconds / 3600 * 10).rounded() / 10)
                ])
            }
        case .showNotification:
            return { args in
                try await services.notifications.post(title: try args.requiredString("title"), message: try args.requiredString("message"))
                return json(["status": "shown"])
            }

        // MARK: Окна
        case .getActiveApplication:
            return { _ in
                guard let name = services.applications.frontmostApplicationName() else {
                    return json(["application": .null])
                }
                var result: [String: JSONValue] = ["application": .string(name)]
                if services.windows.isAccessibilityTrusted {
                    result["focused_window"] = services.windows.focusedWindowTitle(ofApplicationNamed: name).map(JSONValue.string) ?? .null
                } else {
                    result["focused_window"] = .null
                    result["note"] = "Accessibility permission not granted; window title unavailable."
                }
                return json(result)
            }
        case .listWindows:
            return { args in
                let listing = try services.windows.windowTitles(ofApplicationNamed: args.string("application"))
                return json(["application": .string(listing.application), "windows": .array(listing.titles.map(JSONValue.string))])
            }
        case .focusWindow:
            return { args in
                let title = try services.windows.focusWindow(
                    ofApplicationNamed: try args.requiredString("application"),
                    titleContaining: try args.requiredString("window_title")
                )
                return json(["status": "focused", "window": .string(title)])
            }

        // MARK: Проекты
        case .openProject:
            return { args in
                let name = try args.requiredString("project_name")
                let editorRaw = try args.requiredString("editor")
                guard let editor = EditorChoice(rawValue: editorRaw) else {
                    throw ToolValidationError.valueNotAllowed(argument: "editor", value: editorRaw, allowed: ToolCatalog.editors)
                }
                let locator = ProjectLocator(searchPaths: services.settings().projectSearchPaths)
                guard let match = locator.find(projectNamed: name) else {
                    throw AutomationError.projectNotFound(name)
                }
                try await services.projects.open(match, in: editor)
                return json([
                    "status": "opened",
                    "project": .string(match.displayName),
                    "path": .string(match.folderURL.path),
                    "opened_item": .string(match.openTargetURL.lastPathComponent),
                    "editor": .string(editor.rawValue)
                ])
            }
        }
    }

    static func resolveBrowser(_ raw: String?, settings: AppSettings) -> BrowserChoice {
        switch raw {
        case "safari": return .safari
        case "chrome": return .chrome
        default: return settings.preferredBrowser
        }
    }

    static func json(_ object: [String: JSONValue]) -> String {
        JSONValue.object(object).compactString()
    }
}

/// Арифметика громкости (вынесена для тестов).
public enum VolumeMath {
    public static func apply(delta: Int, to current: Int) -> Int {
        min(100, max(0, current + delta))
    }
}

public enum ByteMath {
    /// Десятичные гигабайты (как в Finder), с одним знаком после запятой.
    public static func gigabytes(_ bytes: Int64) -> Double {
        (Double(bytes) / 1_000_000_000 * 10).rounded() / 10
    }

    public static func usedPercent(available: Int64, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        let used = Double(total - available) / Double(total) * 100
        return (used * 10).rounded() / 10
    }
}
