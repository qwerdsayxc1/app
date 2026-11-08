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
        }
    }
}

@MainActor
public protocol ApplicationManaging: AnyObject {
    /// Запускает/активирует приложение, возвращает его фактическое имя.
    func openApplication(named name: String) async throws -> String
    func quitApplication(named name: String) throws -> String
    func switchToApplication(named name: String) throws -> String
    func runningApplicationNames() -> [String]
    func frontmostApplicationName() -> String?
}

@MainActor
public protocol BrowserControlling: AnyObject {
    func open(_ url: URL, in browser: BrowserChoice) async throws
}

@MainActor
public protocol SystemManaging: AnyObject {
    func volume() async throws -> VolumeState
    func setVolume(_ level: Int) async throws
    func setMuted(_ muted: Bool) async throws
    func batteryStatus() throws -> BatteryStatus
    func diskSpace() throws -> DiskSpace
    func systemInfo() -> SystemInfo
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
}

@MainActor
public protocol ProjectOpening: AnyObject {
    func open(_ project: ProjectMatch, in editor: EditorChoice) async throws
}
