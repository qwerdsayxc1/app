import Foundation

// Протоколы сервисов автоматизации. Реализации на AppKit/IOKit/Accessibility живут в
// macOS-приложении (App/…), а логика инструментов и тесты зависят только от протоколов (DIP).

public struct VolumeState: Sendable, Equatable {
    public let level: Int
    public let isMuted: Bool
    public init(level: Int, isMuted: Bool) {
        self.level = level
        self.isMuted = isMuted
    }
}

public struct BatteryStatus: Sendable, Equatable {
    public let percent: Int
    public let isCharging: Bool
    public let isOnACPower: Bool
    /// Оценка оставшегося времени работы в минутах (nil — система ещё считает или идёт зарядка).
    public let minutesRemaining: Int?

    public init(percent: Int, isCharging: Bool, isOnACPower: Bool, minutesRemaining: Int?) {
        self.percent = percent
        self.isCharging = isCharging
        self.isOnACPower = isOnACPower
        self.minutesRemaining = minutesRemaining
    }
}

public struct DiskSpace: Sendable, Equatable {
    public let availableBytes: Int64
    public let totalBytes: Int64
    public init(availableBytes: Int64, totalBytes: Int64) {
        self.availableBytes = availableBytes
        self.totalBytes = totalBytes
    }
}

public struct SystemInfo: Sendable, Equatable {
    public let osVersion: String
    public let modelIdentifier: String
    public let chip: String
    public let memoryBytes: UInt64
    public let cpuCores: Int
    public let uptimeSeconds: TimeInterval

    public init(osVersion: String, modelIdentifier: String, chip: String, memoryBytes: UInt64, cpuCores: Int, uptimeSeconds: TimeInterval) {
        self.osVersion = osVersion
        self.modelIdentifier = modelIdentifier
        self.chip = chip
        self.memoryBytes = memoryBytes
        self.cpuCores = cpuCores
        self.uptimeSeconds = uptimeSeconds
    }
}

public enum EditorChoice: String, Sendable, CaseIterable {
    case xcode, intellij, vscode, finder
}

public enum MediaAction: String, Sendable, CaseIterable {
    case play, pause, toggle, next, previous
}

public enum MediaPlayer: String, Sendable, CaseIterable {
    case auto, music, spotify
}

public struct NowPlaying: Sendable, Equatable {
    public let title: String
    public let artist: String
    public let player: String
    public let isPlaying: Bool

    public init(title: String, artist: String, player: String, isPlaying: Bool) {
        self.title = title
        self.artist = artist
        self.player = player
        self.isPlaying = isPlaying
    }
}

public enum StandardFolder: String, Sendable, CaseIterable {
    case home, desktop, documents, downloads, applications, pictures, music, movies
}

public enum WindowAction: String, Sendable, CaseIterable {
    case minimize
    case restore
    case fullscreen
    case exitFullscreen = "exit_fullscreen"
}

public enum TabAction: String, Sendable, CaseIterable {
    case newTab = "new_tab"
    case closeTab = "close_tab"
    case reload
}

/// Ошибки автоматизации, понятные и пользователю, и модели.
public enum AutomationError: Error, Equatable, Sendable, LocalizedError {
    case applicationNotFound(String)
    case applicationNotRunning(String)
    case launchFailed(String)
    case browserNotInstalled(String)
    case accessibilityNotGranted
    case windowNotFound(application: String, title: String)
    case scriptFailed(String)
    case batteryUnavailable
    case notificationsNotAllowed
    case projectNotFound(String)
    case editorNotInstalled(String)
    case cancelledByUser
    case playerNotAvailable(String)
    case noVideoFound(String)
    case noWindow(String)

    public var errorDescription: String? {
        switch self {
        case .applicationNotFound(let name): return "Application '\(name)' is not installed or could not be found."
        case .applicationNotRunning(let name): return "Application '\(name)' is not running."
        case .launchFailed(let reason): return "Failed to launch: \(reason)"
        case .browserNotInstalled(let name): return "Browser '\(name)' is not installed."
        case .accessibilityNotGranted: return "Accessibility permission is not granted. Ask the user to enable NOVA AI in System Settings › Privacy & Security › Accessibility."
        case let .windowNotFound(application, title): return "No window containing '\(title)' found in \(application)."
        case .scriptFailed(let message): return "System script failed: \(message)"
        case .batteryUnavailable: return "This Mac has no battery information available."
        case .notificationsNotAllowed: return "Notifications are not allowed for NOVA AI."
        case .projectNotFound(let name): return "No project folder matching '\(name)' was found in the configured project folders."
        case .editorNotInstalled(let name): return "Editor '\(name)' is not installed."
        case .cancelledByUser: return "The user declined this action."
        case .playerNotAvailable(let name): return "\(name) is not installed or not running."
        case .noVideoFound(let query): return "No YouTube video found for '\(query)'."
        case .noWindow(let application): return "\(application) has no suitable window."
        }
    }
}

@MainActor
public protocol ApplicationManaging: AnyObject {
    /// Запускает/активирует приложение, возвращает его фактическое имя.
    func openApplication(named name: String) async throws -> String
    func quitApplication(named name: String) throws -> String
    func switchToApplication(named name: String) throws -> String
    func hideApplication(named name: String) throws -> String
    func runningApplicationNames() -> [String]
    func frontmostApplicationName() -> String?
}

@MainActor
public protocol BrowserControlling: AnyObject {
    func open(_ url: URL, in browser: BrowserChoice) async throws
    /// Действие с вкладкой во фронтальном окне; возвращает название браузера.
    func performTabAction(_ action: TabAction, in browser: BrowserChoice) async throws -> String
}

@MainActor
public protocol MediaControlling: AnyObject {
    /// Выполняет действие и возвращает имя плеера, которым управляли.
    func perform(_ action: MediaAction, player: MediaPlayer) async throws -> String
    /// nil — ничего не играет (или плееры не запущены).
    func nowPlaying() async throws -> NowPlaying?
}

/// Поиск видео (для «включи видео …»). Sendable: выполняется вне главного потока.
public protocol VideoSearching: Sendable {
    func firstVideoURL(query: String) async throws -> URL
}

@MainActor
public protocol ProductivityManaging: AnyObject {
    /// Планирует уведомление и возвращает время срабатывания.
    func scheduleTimer(minutes: Int, label: String) async throws -> Date
    func createReminder(title: String) async throws
}

@MainActor
public protocol SystemManaging: AnyObject {
    func volume() async throws -> VolumeState
    func setVolume(_ level: Int) async throws
    func setMuted(_ muted: Bool) async throws
    func batteryStatus() throws -> BatteryStatus
    func diskSpace() throws -> DiskSpace
    func systemInfo() -> SystemInfo
    func setDarkMode(_ enabled: Bool) async throws
    func sleepDisplay() async throws
    /// Снимок экрана на Рабочий стол; возвращает путь к файлу.
    func takeScreenshot() async throws -> URL
    /// Открывает папку в Finder; возвращает её путь.
    func openFolder(_ folder: StandardFolder) throws -> URL
}

@MainActor
public protocol NotificationPosting: AnyObject {
    func post(title: String, message: String) async throws
}

@MainActor
public protocol WindowManaging: AnyObject {
    var isAccessibilityTrusted: Bool { get }
    func focusedWindowTitle(ofApplicationNamed name: String) -> String?
    /// Возвращает фактическое имя приложения и заголовки его окон.
    func windowTitles(ofApplicationNamed name: String?) throws -> (application: String, titles: [String])
    /// Возвращает заголовок окна, которое было выведено на передний план.
    func focusWindow(ofApplicationNamed name: String, titleContaining title: String) throws -> String
    /// Возвращает фактическое имя приложения.
    func performWindowAction(_ action: WindowAction, ofApplicationNamed name: String?) throws -> String
}

@MainActor
public protocol ProjectOpening: AnyObject {
    func open(_ project: ProjectMatch, in editor: EditorChoice) async throws
}
