import Foundation

/// Каталог (белый список) инструментов NOVA AI с описаниями и схемами.
public enum ToolCatalog {
    public static let knownWebsites = ["youtube", "github", "google", "apple", "wikipedia", "stackoverflow", "gmail", "maps"]
    public static let searchEngines = ["google", "youtube", "github"]
    public static let browsers = ["safari", "chrome", "default"]
    public static let editors = ["xcode", "intellij", "vscode", "finder"]

    public static let all: [ToolDefinition] = [
        // MARK: Приложения
        ToolDefinition(
            name: .openApplication,
            description: "Launch a macOS application or bring it to front. Use the application's common name, e.g. 'Telegram', 'Safari', 'IntelliJ IDEA', 'Xcode'.",
            parameters: [
                ToolParameter("name", "Application name as the user said it.", .string(maxLength: 80))
            ]
        ),
        ToolDefinition(
            name: .quitApplication,
            description: "Quit a running application. The user will be asked to confirm because unsaved work may be lost.",
            parameters: [
                ToolParameter("name", "Name of the running application to quit.", .string(maxLength: 80))
            ],
            risk: .requiresConfirmation
        ),
        ToolDefinition(
            name: .switchToApplication,
            description: "Bring an already running application to the front.",
            parameters: [
                ToolParameter("name", "Name of the running application.", .string(maxLength: 80))
            ]
        ),
        ToolDefinition(
            name: .listRunningApplications,
            description: "List the regular (Dock-visible) applications that are currently running."
        ),

        // MARK: Браузер
        ToolDefinition(
            name: .openURL,
            description: "Open a web page in the browser.",
            parameters: [
                ToolParameter("url", "Full URL to open.", .string(maxLength: 2048, format: .webURL)),
                ToolParameter("browser", "Browser to use; 'default' uses the user's preference.", .string(maxLength: 16, allowedValues: browsers), required: false)
            ]
        ),
        ToolDefinition(
            name: .openWebsite,
            description: "Open a well-known website by name (YouTube, GitHub, Google, Apple, Wikipedia, Stack Overflow, Gmail, Google Maps).",
            parameters: [
                ToolParameter("site", "Website identifier.", .string(maxLength: 32, allowedValues: knownWebsites)),
                ToolParameter("browser", "Browser to use; 'default' uses the user's preference.", .string(maxLength: 16, allowedValues: browsers), required: false)
            ]
        ),
        ToolDefinition(
            name: .webSearch,
            description: "Search the web: Google search, YouTube video search or GitHub repository search. Opens the results page in the browser.",
            parameters: [
                ToolParameter("engine", "Where to search.", .string(maxLength: 16, allowedValues: searchEngines)),
                ToolParameter("query", "Search query, in the language the user used.", .string(maxLength: 300)),
                ToolParameter("browser", "Browser to use; 'default' uses the user's preference.", .string(maxLength: 16, allowedValues: browsers), required: false)
            ]
        ),

        // MARK: Система
        ToolDefinition(
            name: .getVolume,
            description: "Get the current output volume (0-100) and whether sound is muted."
        ),
        ToolDefinition(
            name: .setVolume,
            description: "Set the output volume to an absolute level in percent.",
            parameters: [
                ToolParameter("level", "Target volume in percent.", .integer(min: 0, max: 100))
            ]
        ),
        ToolDefinition(
            name: .changeVolume,
            description: "Change the output volume relatively, e.g. +20 to make it louder by 20 percentage points, -10 to make it quieter.",
            parameters: [
                ToolParameter("delta", "Change in percentage points (negative = quieter).", .integer(min: -100, max: 100))
            ]
        ),
        ToolDefinition(
            name: .setMute,
            description: "Mute or unmute the system sound output.",
            parameters: [
                ToolParameter("muted", "true to mute, false to unmute.", .boolean)
            ]
        ),
        ToolDefinition(
            name: .getBatteryStatus,
            description: "Get battery charge percentage, charging state and time remaining."
        ),
        ToolDefinition(
            name: .getDiskSpace,
            description: "Get free and total space on the startup disk."
        ),
        ToolDefinition(
            name: .getSystemInfo,
            description: "Get macOS version, Mac model, chip, memory, CPU cores and uptime."
        ),
        ToolDefinition(
            name: .showNotification,
            description: "Show a local macOS notification from NOVA.",
            parameters: [
                ToolParameter("title", "Notification title.", .string(maxLength: 80)),
                ToolParameter("message", "Notification body text.", .string(maxLength: 300))
            ]
        ),

        // MARK: Окна
        ToolDefinition(
            name: .getActiveApplication,
            description: "Get the frontmost application and the title of its focused window."
        ),
        ToolDefinition(
            name: .listWindows,
            description: "List window titles of an application (or of the frontmost application if no name is given). Requires Accessibility permission.",
            parameters: [
                ToolParameter("application", "Application name; omit for the frontmost app.", .string(maxLength: 80), required: false)
            ]
        ),
        ToolDefinition(
            name: .focusWindow,
            description: "Bring a specific window of an application to the front by (partial) title. Requires Accessibility permission.",
            parameters: [
                ToolParameter("application", "Application name.", .string(maxLength: 80)),
                ToolParameter("window_title", "Full or partial window title.", .string(maxLength: 200))
            ]
        ),

        // MARK: Проекты
        ToolDefinition(
            name: .openProject,
            description: "Find a local software project folder by name (e.g. 'NOVA AI') in the user's project folders and open it in an editor.",
            parameters: [
                ToolParameter("project_name", "Project name as the user said it.", .string(maxLength: 120)),
                ToolParameter("editor", "Editor to open the project in.", .string(maxLength: 16, allowedValues: editors))
            ]
        )
    ]

    private static let byName: [ToolName: ToolDefinition] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.name, $0) }
    )

    /// Определение по имени из ответа модели; nil — инструмент не в белом списке.
    public static func definition(named rawName: String) -> ToolDefinition? {
        guard let name = ToolName(rawValue: rawName) else { return nil }
        return byName[name]
    }

    public static func definition(for name: ToolName) -> ToolDefinition {
        // Каталог покрывает все case'ы ToolName — это проверяется тестом.
        guard let definition = byName[name] else {
            preconditionFailure("ToolCatalog не содержит \(name.rawValue)")
        }
        return definition
    }

    /// Массив `tools` для Messages API (порядок стабилен — важно для кеширования).
    public static func apiTools(_ definitions: [ToolDefinition] = all) -> JSONValue {
        .array(definitions.map { $0.apiDefinition() })
    }
}
