import XCTest
@testable import NOVACore

@MainActor
final class ToolManagerTests: XCTestCase {
    func testUnknownToolReturnsErrorResultWithoutExecuting() async {
        let env = FakeEnvironment()
        let manager = env.toolManager()
        let record = await manager.execute(ToolCall(id: "t1", name: "run_shell", input: ["command": "ls"]))
        XCTAssertTrue(record.result.isError)
        XCTAssertEqual(record.result.toolUseID, "t1")
        XCTAssertTrue(record.result.content.contains("not in the allowed tool list"))
    }

    func testInvalidArgumentsDoNotReachHandler() async {
        let env = FakeEnvironment()
        let manager = env.toolManager()
        let record = await manager.execute(ToolCall(id: "t1", name: "set_volume", input: ["level": 500]))
        XCTAssertTrue(record.result.isError)
        XCTAssertEqual(env.system.level, 50, "громкость не должна измениться")
    }

    func testOpenTelegramUsesAlias() async {
        let env = FakeEnvironment()
        let record = await env.toolManager().execute(ToolCall(id: "t1", name: "open_application", input: ["name": "телеграм"]))
        XCTAssertFalse(record.result.isError)
        XCTAssertEqual(env.apps.opened, ["Telegram"])
    }

    func testChangeVolumeByTwentyPercentAndClamp() async {
        let env = FakeEnvironment()
        let manager = env.toolManager()
        env.system.level = 50
        _ = await manager.execute(ToolCall(id: "t1", name: "change_volume", input: ["delta": 20]))
        XCTAssertEqual(env.system.level, 70)
        env.system.level = 95
        let record = await manager.execute(ToolCall(id: "t2", name: "change_volume", input: ["delta": 20]))
        XCTAssertEqual(env.system.level, 100)
        XCTAssertTrue(record.result.content.contains("\"clamped\":true"))
    }

    func testLouderUnmutes() async {
        let env = FakeEnvironment()
        env.system.muted = true
        _ = await env.toolManager().execute(ToolCall(id: "t1", name: "change_volume", input: ["delta": 10]))
        XCTAssertFalse(env.system.muted)
    }

    func testMute() async {
        let env = FakeEnvironment()
        _ = await env.toolManager().execute(ToolCall(id: "t1", name: "set_mute", input: ["muted": true]))
        XCTAssertTrue(env.system.muted)
    }

    func testBatteryResult() async throws {
        let env = FakeEnvironment()
        let record = await env.toolManager().execute(ToolCall(id: "t1", name: "get_battery_status", input: [:]))
        let json = try JSONValue.decode(from: Data(record.result.content.utf8))
        XCTAssertEqual(json["percent"]?.intValue, 82)
        XCTAssertEqual(json["charging"]?.boolValue, false)
    }

    func testBatteryUnavailableIsError() async {
        let env = FakeEnvironment()
        env.system.battery = nil
        let record = await env.toolManager().execute(ToolCall(id: "t1", name: "get_battery_status", input: [:]))
        XCTAssertTrue(record.result.isError)
    }

    func testYouTubeSearchOpensResultsInPreferredBrowser() async throws {
        var env = FakeEnvironment()
        env.settings.preferredBrowser = .chrome
        let record = await env.toolManager().execute(ToolCall(id: "t1", name: "web_search", input: ["engine": "youtube", "query": "видео про Python"]))
        XCTAssertFalse(record.result.isError, record.result.content)
        let (url, browser) = try XCTUnwrap(env.browser.opened.first)
        XCTAssertEqual(browser, .chrome)
        XCTAssertEqual(url.host, "www.youtube.com")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "видео про Python")
    }

    func testOpenURLExplicitSafari() async throws {
        let env = FakeEnvironment()
        _ = await env.toolManager().execute(ToolCall(id: "t1", name: "open_url", input: ["url": "https://www.apple.com", "browser": "safari"]))
        let (url, browser) = try XCTUnwrap(env.browser.opened.first)
        XCTAssertEqual(url.absoluteString, "https://www.apple.com")
        XCTAssertEqual(browser, .safari)
    }

    func testListRunningApps() async throws {
        let env = FakeEnvironment()
        let record = await env.toolManager().execute(ToolCall(id: "t1", name: "list_running_applications", input: [:]))
        let json = try JSONValue.decode(from: Data(record.result.content.utf8))
        XCTAssertEqual(json["applications"]?.arrayValue?.compactMap(\.stringValue), ["Finder", "Safari"])
    }

    // MARK: Подтверждение

    func testDangerousActionDeniedWithoutProvider() async {
        let env = FakeEnvironment()
        let record = await env.toolManager(confirmation: nil).execute(ToolCall(id: "t1", name: "quit_application", input: ["name": "Safari"]))
        XCTAssertTrue(record.result.isError)
        XCTAssertTrue(env.apps.quit.isEmpty, "fail closed: без подтверждения ничего не закрываем")
    }

    func testDangerousActionDeniedByUser() async {
        let env = FakeEnvironment()
        let confirmation = FakeConfirmation(answer: false)
        let record = await env.toolManager(confirmation: confirmation).execute(ToolCall(id: "t1", name: "quit_application", input: ["name": "Safari"]))
        XCTAssertTrue(record.result.isError)
        XCTAssertEqual(confirmation.requests.count, 1)
        XCTAssertTrue(confirmation.requests[0].prompt.contains("Safari"))
        XCTAssertTrue(env.apps.quit.isEmpty)
    }

    func testDangerousActionApproved() async {
        let env = FakeEnvironment()
        let confirmation = FakeConfirmation(answer: true)
        let record = await env.toolManager(confirmation: confirmation).execute(ToolCall(id: "t1", name: "quit_application", input: ["name": "Safari"]))
        XCTAssertFalse(record.result.isError, record.result.content)
        XCTAssertEqual(env.apps.quit, ["Safari"])
    }

    func testSafeActionDoesNotAskForConfirmation() async {
        let env = FakeEnvironment()
        let confirmation = FakeConfirmation(answer: false)
        _ = await env.toolManager(confirmation: confirmation).execute(ToolCall(id: "t1", name: "open_application", input: ["name": "Safari"]))
        XCTAssertTrue(confirmation.requests.isEmpty)
    }

    // MARK: Окна

    func testFocusWindowRequiresAccessibility() async {
        let env = FakeEnvironment()
        env.windows.isAccessibilityTrusted = false
        let record = await env.toolManager().execute(ToolCall(id: "t1", name: "focus_window", input: ["application": "Safari", "window_title": "git"]))
        XCTAssertTrue(record.result.isError)
        XCTAssertTrue(record.result.content.contains("Accessibility"))
    }

    func testActiveApplicationIncludesWindowTitle() async throws {
        let env = FakeEnvironment()
        let record = await env.toolManager().execute(ToolCall(id: "t1", name: "get_active_application", input: [:]))
        let json = try JSONValue.decode(from: Data(record.result.content.utf8))
        XCTAssertEqual(json["application"]?.stringValue, "Safari")
        XCTAssertEqual(json["focused_window"]?.stringValue, "Apple")
    }

    func testToolResultAPIBlock() {
        let block = ToolResult(toolUseID: "toolu_1", content: "boom", isError: true).apiBlock
        XCTAssertEqual(block["type"]?.stringValue, "tool_result")
        XCTAssertEqual(block["tool_use_id"]?.stringValue, "toolu_1")
        XCTAssertEqual(block["is_error"]?.boolValue, true)
        XCTAssertNil(ToolResult(toolUseID: "x", content: "ok", isError: false).apiBlock["is_error"])
    }
}
