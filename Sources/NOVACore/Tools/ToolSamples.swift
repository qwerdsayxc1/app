import Foundation

/// Примеры вызовов для проверки инструментов без Claude
/// (экран «Проверка» в настройках и самопроверка в CI).
public enum ToolSamples {
    /// Безопасный пример аргументов для каждого инструмента.
    public static func sample(for tool: ToolName) -> JSONValue {
        switch tool {
        case .openApplication: return ["name": "Calculator"]
        case .quitApplication: return ["name": "Calculator"]
        case .switchToApplication: return ["name": "Finder"]
        case .listRunningApplications: return [:]
        case .openURL: return ["url": "https://www.apple.com", "browser": "default"]
        case .openWebsite: return ["site": "youtube", "browser": "default"]
        case .webSearch: return ["engine": "google", "query": "Claude API", "browser": "default"]
        case .getVolume: return [:]
        case .setVolume: return ["level": 30]
        case .changeVolume: return ["delta": 10]
        case .setMute: return ["muted": false]
        case .getBatteryStatus: return [:]
        case .getDiskSpace: return [:]
        case .getSystemInfo: return [:]
        case .showNotification: return ["title": "NOVA AI", "message": "Проверка уведомлений"]
        case .getActiveApplication: return [:]
        case .listWindows: return [:]
        case .focusWindow: return ["application": "Finder", "window_title": "Downloads"]
        case .openProject: return ["project_name": "NOVA AI", "editor": "finder"]
        case .playYouTubeVideo: return ["query": "Swift programming tutorial", "browser": "default"]
        case .mediaControl: return ["action": "toggle", "player": "auto"]
        case .nowPlaying: return [:]
        case .browserTab: return ["action": "new_tab", "browser": "safari"]
        case .getDateTime: return [:]
        case .setTimer: return ["minutes": 1, "label": "Проверка таймера NOVA"]
        case .createReminder: return ["title": "Проверка NOVA AI"]
        case .openFolder: return ["folder": "downloads"]
        case .takeScreenshot: return [:]
        case .setDarkMode: return ["enabled": true]
        case .sleepDisplay: return [:]
        case .hideApplication: return ["name": "Calculator"]
        case .windowAction: return ["action": "minimize"]
        }
    }

    /// Последовательность для автоматической самопроверки на чистом Mac без человека.
    /// Исключено то, что требует нажать «Разрешить» в системном диалоге (Автоматизация,
    /// «Напоминания», Music) или мешает машине (выключение экрана, закрытие приложений) —
    /// такие действия проверяются на экране «Проверка» на живом Mac.
    public static let selfTestSequence: [ToolCall] = [
        call(.getDateTime),
        call(.getSystemInfo),
        call(.getDiskSpace),
        call(.getBatteryStatus),
        call(.listRunningApplications),
        call(.getActiveApplication),
        call(.getVolume),
        call(.setVolume),
        call(.changeVolume),
        call(.setMute),
        call(.openApplication),
        call(.switchToApplication),
        call(.openFolder),
        call(.openURL),
        call(.webSearch, ["engine": "wikipedia", "query": "macOS", "browser": "default"]),
        call(.playYouTubeVideo),
        call(.nowPlaying),
        call(.listWindows),
        call(.takeScreenshot),
        call(.openProject, ["project_name": "app", "editor": "finder"]),
        call(.showNotification),
        call(.setTimer)
    ]

    private static func call(_ tool: ToolName, _ input: JSONValue? = nil) -> ToolCall {
        ToolCall(id: "selftest_\(tool.rawValue)", name: tool.rawValue, input: input ?? sample(for: tool))
    }
}
