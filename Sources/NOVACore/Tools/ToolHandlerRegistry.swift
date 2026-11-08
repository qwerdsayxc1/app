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
    public let media: MediaControlling
    public let videos: VideoSearching
    public let productivity: ProductivityManaging
    public let settings: () -> AppSettings
    public let now: () -> Date
    public let timeZone: TimeZone

    public init(
        applications: ApplicationManaging,
        browser: BrowserControlling,
        system: SystemManaging,
        notifications: NotificationPosting,
        windows: WindowManaging,
        projects: ProjectOpening,
        media: MediaControlling,
        videos: VideoSearching,
        productivity: ProductivityManaging,
        settings: @escaping () -> AppSettings,
        now: @escaping () -> Date = { Date() },
        timeZone: TimeZone = .current
    ) {
        self.applications = applications
        self.browser = browser
        self.system = system
        self.notifications = notifications
        self.windows = windows
        self.projects = projects
        self.media = media
        self.videos = videos
        self.productivity = productivity
        self.settings = settings
        self.now = now
        self.timeZone = timeZone
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
                let settings = services.settings()
                guard let url = WebURLBuilder.searchURL(engine: engine, query: query, language: settings.language) else {
                    throw ToolValidationError.valueNotAllowed(argument: "engine", value: engine, allowed: ToolCatalog.searchEngines)
                }
                let browser = resolveBrowser(args.string("browser"), settings: settings)
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

        // MARK: Медиа
        case .playYouTubeVideo:
            return { args in
                let query = try args.requiredString("query")
                let browser = resolveBrowser(args.string("browser"), settings: services.settings())
                do {
                    let videoURL = try await services.videos.firstVideoURL(query: query)
                    try await services.browser.open(videoURL, in: browser)
                    return json(["status": "playing_first_result", "query": .string(query), "url": .string(videoURL.absoluteString)])
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Не удалось найти конкретный ролик — открываем результаты поиска, чтобы команда всё равно сработала.
                    guard let searchURL = WebURLBuilder.searchURL(engine: "youtube", query: query) else { throw error }
                    try await services.browser.open(searchURL, in: browser)
                    return json([
                        "status": "opened_search_results_instead",
                        "reason": .string(ToolManager.describe(error)),
                        "query": .string(query)
                    ])
                }
            }
        case .mediaControl:
            return { args in
                let actionRaw = try args.requiredString("action")
                guard let action = MediaAction(rawValue: actionRaw) else {
                    throw ToolValidationError.valueNotAllowed(argument: "action", value: actionRaw, allowed: ToolCatalog.mediaActions)
                }
                let player = args.string("player").flatMap(MediaPlayer.init(rawValue:)) ?? .auto
                let used = try await services.media.perform(action, player: player)
                return json(["status": "done", "action": .string(action.rawValue), "player": .string(used)])
            }
        case .nowPlaying:
            return { _ in
                guard let track = try await services.media.nowPlaying() else {
                    return json(["playing": false, "note": "Nothing is playing in Music or Spotify."])
                }
                return json([
                    "playing": .bool(track.isPlaying),
                    "title": .string(track.title),
                    "artist": .string(track.artist),
                    "player": .string(track.player)
                ])
            }

        // MARK: Вкладки
        case .browserTab:
            return { args in
                let actionRaw = try args.requiredString("action")
                guard let action = TabAction(rawValue: actionRaw) else {
                    throw ToolValidationError.valueNotAllowed(argument: "action", value: actionRaw, allowed: ToolCatalog.tabActions)
                }
                let browser: BrowserChoice = try args.requiredString("browser") == "chrome" ? .chrome : .safari
                let name = try await services.browser.performTabAction(action, in: browser)
                return json(["status": "done", "action": .string(action.rawValue), "browser": .string(name)])
            }

        // MARK: Продуктивность
        case .getDateTime:
            return { _ in
                DateTimeFormatter.describe(services.now(), timeZone: services.timeZone)
            }
        case .setTimer:
            return { args in
                let minutes = try args.requiredInt("minutes")
                let label = args.string("label") ?? TimerText.defaultLabel(services.settings().language)
                let fireDate = try await services.productivity.scheduleTimer(minutes: minutes, label: label)
                return json([
                    "status": "scheduled",
                    "minutes": .number(Double(minutes)),
                    "fires_at": .string(DateTimeFormatter.timeString(fireDate, timeZone: services.timeZone)),
                    "label": .string(label)
                ])
            }
        case .createReminder:
            return { args in
                let title = try args.requiredString("title")
                try await services.productivity.createReminder(title: title)
                return json(["status": "created", "title": .string(title)])
            }

        // MARK: Система (дополнительно)
        case .openFolder:
            return { args in
                let raw = try args.requiredString("folder")
                guard let folder = StandardFolder(rawValue: raw) else {
                    throw ToolValidationError.valueNotAllowed(argument: "folder", value: raw, allowed: ToolCatalog.folders)
                }
                let url = try services.system.openFolder(folder)
                return json(["status": "opened", "folder": .string(folder.rawValue), "path": .string(url.path)])
            }
        case .takeScreenshot:
            return { _ in
                let url = try await services.system.takeScreenshot()
                return json(["status": "saved", "file": .string(url.lastPathComponent), "location": "Desktop"])
            }
        case .setDarkMode:
            return { args in
                let enabled = try args.requiredBool("enabled")
                try await services.system.setDarkMode(enabled)
                return json(["dark_mode": .bool(enabled)])
            }
        case .sleepDisplay:
            return { _ in
                try await services.system.sleepDisplay()
                return json(["status": "display_sleeping"])
            }

        // MARK: Приложения и окна (дополнительно)
        case .hideApplication:
            return { args in
                let hidden = try services.applications.hideApplication(named: try args.requiredString("name"))
                return json(["status": "hidden", "application": .string(hidden)])
            }
        case .windowAction:
            return { args in
                let raw = try args.requiredString("action")
                guard let action = WindowAction(rawValue: raw) else {
                    throw ToolValidationError.valueNotAllowed(argument: "action", value: raw, allowed: ToolCatalog.windowActions)
                }
                let app = try services.windows.performWindowAction(action, ofApplicationNamed: args.string("application"))
                return json(["status": "done", "action": .string(action.rawValue), "application": .string(app)])
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

/// Дата и время для модели — локальное время Mac в однозначном формате.
public enum DateTimeFormatter {
    public static func describe(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let weekday = parts.weekday.map { weekdays[($0 - 1 + 7) % 7] } ?? ""
        let dateString = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return JSONValue.object([
            "date": .string(dateString),
            "time": .string(timeString(date, timeZone: timeZone)),
            "weekday": .string(weekday),
            "time_zone": .string(timeZone.identifier)
        ]).compactString()
    }

    public static func timeString(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

public enum TimerText {
    public static func defaultLabel(_ language: SupportedLanguage) -> String {
        switch language {
        case .russian: return "Время вышло"
        case .ukrainian: return "Час вийшов"
        case .english: return "Time is up"
        case .german: return "Die Zeit ist um"
        }
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
