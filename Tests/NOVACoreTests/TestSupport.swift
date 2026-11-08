import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NOVACore

// MARK: - JSON helpers

func messageJSON(
    id: String = "msg_test",
    content: [JSONValue],
    stopReason: String,
    stopDetails: JSONValue = .null
) -> JSONValue {
    [
        "id": .string(id),
        "type": "message",
        "role": "assistant",
        "model": "claude-opus-5-5",
        "content": .array(content),
        "stop_reason": .string(stopReason),
        "stop_details": stopDetails,
        "usage": ["input_tokens": 120, "output_tokens": 30, "cache_read_input_tokens": 100]
    ]
}

func textBlock(_ text: String) -> JSONValue {
    ["type": "text", "text": .string(text)]
}

func toolUseBlock(id: String, name: String, input: JSONValue) -> JSONValue {
    ["type": "tool_use", "id": .string(id), "name": .string(name), "input": input]
}

func thinkingBlock() -> JSONValue {
    ["type": "thinking", "thinking": "", "signature": "sig_abc"]
}

// MARK: - Scripted Claude

/// Возвращает заранее заданные ответы и запоминает запросы.
final class ScriptedClaude: ClaudeMessaging, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [Result<ClaudeResponse, Error>]
    private(set) var receivedMessages: [[JSONValue]] = []
    private(set) var receivedTools: [[ToolDefinition]] = []
    private(set) var receivedConfigurations: [ClaudeConfiguration] = []

    init(_ responses: [JSONValue]) {
        self.responses = responses.map { json in
            Result { try ClaudeResponseParser.parse(json) }
        }
    }

    init(results: [Result<ClaudeResponse, Error>]) {
        self.responses = results
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return receivedMessages.count
    }

    func send(system: String, messages: [JSONValue], tools: [ToolDefinition], configuration: ClaudeConfiguration) async throws -> ClaudeResponse {
        // NSLock.lock()/unlock() недоступны в async-контексте Swift 6 — используем withLock.
        let next: Result<ClaudeResponse, Error>? = lock.withLock {
            receivedMessages.append(messages)
            receivedTools.append(tools)
            receivedConfigurations.append(configuration)
            return responses.isEmpty ? nil : responses.removeFirst()
        }
        guard let next else {
            throw ClaudeAPIError.invalidResponse("script exhausted")
        }
        return try next.get()
    }
}

// MARK: - Mock HTTP transport

final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Reply {
        let status: Int
        let body: Data
        let headers: [String: String]
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply? = lock.withLock {
            requests.append(request)
            return replies.isEmpty ? nil : replies.removeFirst()
        }
        guard let reply else { throw URLError(.notConnectedToInternet) }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: reply.headers
        )!
        return (reply.body, response)
    }
}

// MARK: - Fake automation services

@MainActor
final class FakeApplications: ApplicationManaging {
    var running: [String] = ["Finder", "Safari"]
    var opened: [String] = []
    var quit: [String] = []
    var frontmost: String? = "Safari"

    func openApplication(named name: String) async throws -> String {
        let resolved = AppAliasResolver().resolve(name)?.canonicalName ?? name
        opened.append(resolved)
        if !running.contains(resolved) { running.append(resolved) }
        return resolved
    }

    func quitApplication(named name: String) throws -> String {
        guard let index = running.firstIndex(where: { $0.lowercased() == name.lowercased() }) else {
            throw AutomationError.applicationNotRunning(name)
        }
        let app = running.remove(at: index)
        quit.append(app)
        return app
    }

    func switchToApplication(named name: String) throws -> String {
        guard let app = running.first(where: { $0.lowercased() == name.lowercased() }) else {
            throw AutomationError.applicationNotRunning(name)
        }
        frontmost = app
        return app
    }

    var hidden: [String] = []
    func hideApplication(named name: String) throws -> String {
        guard let app = running.first(where: { $0.lowercased() == name.lowercased() }) else {
            throw AutomationError.applicationNotRunning(name)
        }
        hidden.append(app)
        return app
    }

    func runningApplicationNames() -> [String] { running }
    func frontmostApplicationName() -> String? { frontmost }
}

@MainActor
final class FakeBrowser: BrowserControlling {
    var opened: [(URL, BrowserChoice)] = []
    var tabActions: [(TabAction, BrowserChoice)] = []
    func open(_ url: URL, in browser: BrowserChoice) async throws {
        opened.append((url, browser))
    }
    func performTabAction(_ action: TabAction, in browser: BrowserChoice) async throws -> String {
        tabActions.append((action, browser))
        return browser == .chrome ? "Google Chrome" : "Safari"
    }
}

@MainActor
final class FakeMedia: MediaControlling {
    var actions: [(MediaAction, MediaPlayer)] = []
    var current: NowPlaying? = NowPlaying(title: "Bohemian Rhapsody", artist: "Queen", player: "Music", isPlaying: true)
    func perform(_ action: MediaAction, player: MediaPlayer) async throws -> String {
        actions.append((action, player))
        return player == .spotify ? "Spotify" : "Music"
    }
    func nowPlaying() async throws -> NowPlaying? { current }
}

final class FakeVideos: VideoSearching, @unchecked Sendable {
    var result: Result<URL, Error> = .success(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!)
    func firstVideoURL(query: String) async throws -> URL { try result.get() }
}

@MainActor
final class FakeProductivity: ProductivityManaging {
    var timers: [(Int, String)] = []
    var reminders: [String] = []
    func scheduleTimer(minutes: Int, label: String) async throws -> Date {
        timers.append((minutes, label))
        return Date(timeIntervalSince1970: 0).addingTimeInterval(Double(minutes) * 60)
    }
    func createReminder(title: String) async throws { reminders.append(title) }
}

@MainActor
final class FakeSystem: SystemManaging {
    var level = 50
    var muted = false
    var battery: BatteryStatus? = BatteryStatus(percent: 82, isCharging: false, isOnACPower: false, minutesRemaining: 240)

    func volume() async throws -> VolumeState { VolumeState(level: level, isMuted: muted) }
    func setVolume(_ level: Int) async throws { self.level = level }
    func setMuted(_ muted: Bool) async throws { self.muted = muted }
    func batteryStatus() throws -> BatteryStatus {
        guard let battery else { throw AutomationError.batteryUnavailable }
        return battery
    }
    func diskSpace() throws -> DiskSpace { DiskSpace(availableBytes: 250_000_000_000, totalBytes: 1_000_000_000_000) }
    func systemInfo() -> SystemInfo {
        SystemInfo(osVersion: "macOS 15.1", modelIdentifier: "Mac15,6", chip: "Apple M3 Pro", memoryBytes: 18_000_000_000, cpuCores: 11, uptimeSeconds: 7200)
    }
    var darkMode = false
    var displaySleeping = false
    var screenshots = 0
    var openedFolders: [StandardFolder] = []
    func setDarkMode(_ enabled: Bool) async throws { darkMode = enabled }
    func sleepDisplay() async throws { displaySleeping = true }
    func takeScreenshot() async throws -> URL {
        screenshots += 1
        return URL(fileURLWithPath: "/Users/test/Desktop/NOVA Screenshot.png")
    }
    func openFolder(_ folder: StandardFolder) throws -> URL {
        openedFolders.append(folder)
        return URL(fileURLWithPath: "/Users/test/\(folder.rawValue.capitalized)")
    }
}

@MainActor
final class FakeNotifications: NotificationPosting {
    var posted: [(String, String)] = []
    func post(title: String, message: String) async throws { posted.append((title, message)) }
}

@MainActor
final class FakeWindows: WindowManaging {
    var isAccessibilityTrusted = true
    var windows: [String: [String]] = ["Safari": ["Apple", "GitHub"]]

    func focusedWindowTitle(ofApplicationNamed name: String) -> String? { windows[name]?.first }

    func windowTitles(ofApplicationNamed name: String?) throws -> (application: String, titles: [String]) {
        guard isAccessibilityTrusted else { throw AutomationError.accessibilityNotGranted }
        let app = name ?? "Safari"
        return (app, windows[app] ?? [])
    }

    func focusWindow(ofApplicationNamed name: String, titleContaining title: String) throws -> String {
        guard isAccessibilityTrusted else { throw AutomationError.accessibilityNotGranted }
        guard let match = windows[name]?.first(where: { $0.localizedCaseInsensitiveContains(title) }) else {
            throw AutomationError.windowNotFound(application: name, title: title)
        }
        return match
    }

    var windowActions: [(WindowAction, String?)] = []
    func performWindowAction(_ action: WindowAction, ofApplicationNamed name: String?) throws -> String {
        guard isAccessibilityTrusted else { throw AutomationError.accessibilityNotGranted }
        windowActions.append((action, name))
        return name ?? "Safari"
    }
}

@MainActor
final class FakeProjects: ProjectOpening {
    var opened: [(ProjectMatch, EditorChoice)] = []
    func open(_ project: ProjectMatch, in editor: EditorChoice) async throws {
        opened.append((project, editor))
    }
}

@MainActor
final class FakeConfirmation: ConfirmationProviding {
    var answer: Bool
    var requests: [ConfirmationRequest] = []
    init(answer: Bool) { self.answer = answer }
    func requestConfirmation(_ request: ConfirmationRequest) async -> Bool {
        requests.append(request)
        return answer
    }
}

/// Полный набор фейков для обработчиков инструментов.
@MainActor
struct FakeEnvironment {
    let apps = FakeApplications()
    let browser = FakeBrowser()
    let system = FakeSystem()
    let notifications = FakeNotifications()
    let windows = FakeWindows()
    let projects = FakeProjects()
    let media = FakeMedia()
    let videos = FakeVideos()
    let productivity = FakeProductivity()
    var settings = AppSettings(cloudProcessingConsent: true)
    /// 2026-03-15 14:05 UTC, воскресенье.
    var now = Date(timeIntervalSince1970: 1_773_583_500)

    func services() -> ToolServices {
        let settings = self.settings
        let now = self.now
        return ToolServices(
            applications: apps,
            browser: browser,
            system: system,
            notifications: notifications,
            windows: windows,
            projects: projects,
            media: media,
            videos: videos,
            productivity: productivity,
            settings: { settings },
            now: { now },
            // Не "UTC": на macOS его identifier — "GMT". Берлин в марте — UTC+1.
            timeZone: TimeZone(identifier: "Europe/Berlin")!
        )
    }

    func toolManager(confirmation: ConfirmationProviding? = nil) -> ToolManager {
        ToolManager(handlers: ToolHandlerRegistry.makeHandlers(services()), confirmationProvider: confirmation)
    }
}
