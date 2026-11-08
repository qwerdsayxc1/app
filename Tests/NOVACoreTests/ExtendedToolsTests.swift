import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NOVACore

@MainActor
final class ExtendedToolsTests: XCTestCase {
    private func run(_ env: FakeEnvironment, _ name: String, _ input: JSONValue = [:]) async -> ToolExecutionRecord {
        await env.toolManager().execute(ToolCall(id: "t", name: name, input: input))
    }

    private func json(_ record: ToolExecutionRecord) throws -> JSONValue {
        try JSONValue.decode(from: Data(record.result.content.utf8))
    }

    // MARK: YouTube

    func testPlayYouTubeVideoOpensFirstResult() async throws {
        let env = FakeEnvironment()
        let record = await run(env, "play_youtube_video", ["query": "Как выучить Python за месяц"])
        XCTAssertFalse(record.result.isError, record.result.content)
        XCTAssertEqual(try json(record)["status"]?.stringValue, "playing_first_result")
        XCTAssertEqual(env.browser.opened.first?.0.absoluteString, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    func testPlayYouTubeVideoFallsBackToSearchResults() async throws {
        let env = FakeEnvironment()
        env.videos.result = .failure(VideoSearchError.noResults("x"))
        let record = await run(env, "play_youtube_video", ["query": "редкое видео"])
        XCTAssertFalse(record.result.isError)
        XCTAssertEqual(try json(record)["status"]?.stringValue, "opened_search_results_instead")
        XCTAssertEqual(env.browser.opened.first?.0.host, "www.youtube.com")
        XCTAssertEqual(env.browser.opened.first?.0.path, "/results")
    }

    func testYouTubeParser() {
        let html = #"{"channelId":"UCabc","videoId":"bad"}..."videoId":"dQw4w9WgXcQ","title":{...}..."videoId":"aaaaaaaaaaa""#
        XCTAssertEqual(YouTubeResultParser.firstVideoID(in: html), "dQw4w9WgXcQ")
        XCTAssertNil(YouTubeResultParser.firstVideoID(in: "<html>consent</html>"))
        XCTAssertNil(YouTubeResultParser.firstVideoID(in: #""videoId":"short""#))
        XCTAssertTrue(YouTubeResultParser.isValidVideoID("abc_DEF-123"))
        XCTAssertFalse(YouTubeResultParser.isValidVideoID("abc/DEF-123"))
    }

    func testYouTubeSearchServiceUsesTransport() async throws {
        let html = Data(#"<script>var ytInitialData = {"videoId":"M7lc1UVf-VE"}</script>"#.utf8)
        let transport = MockTransport([.init(status: 200, body: html, headers: [:])])
        let url = try await YouTubeSearchService(transport: transport).firstVideoURL(query: "youtube api")
        XCTAssertEqual(url.absoluteString, "https://www.youtube.com/watch?v=M7lc1UVf-VE")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.host, "www.youtube.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "SOCS=CAI")
    }

    func testYouTubeSearchServiceNoResults() async {
        let transport = MockTransport([.init(status: 200, body: Data("<html></html>".utf8), headers: [:])])
        do {
            _ = try await YouTubeSearchService(transport: transport).firstVideoURL(query: "q")
            XCTFail("ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? VideoSearchError, .noResults("q"))
        }
    }

    // MARK: Музыка

    func testMediaControl() async throws {
        let env = FakeEnvironment()
        let record = await run(env, "media_control", ["action": "next", "player": "spotify"])
        XCTAssertFalse(record.result.isError, record.result.content)
        XCTAssertEqual(env.media.actions.first?.0, .next)
        XCTAssertEqual(env.media.actions.first?.1, .spotify)
        XCTAssertEqual(try json(record)["player"]?.stringValue, "Spotify")
    }

    func testMediaControlDefaultsToAutoAndRejectsUnknownAction() async {
        let env = FakeEnvironment()
        _ = await run(env, "media_control", ["action": "pause"])
        XCTAssertEqual(env.media.actions.first?.1, .auto)
        let bad = await run(env, "media_control", ["action": "rewind"])
        XCTAssertTrue(bad.result.isError)
    }

    func testNowPlaying() async throws {
        let env = FakeEnvironment()
        var record = await run(env, "now_playing")
        XCTAssertEqual(try json(record)["artist"]?.stringValue, "Queen")
        env.media.current = nil
        record = await run(env, "now_playing")
        XCTAssertEqual(try json(record)["playing"]?.boolValue, false)
    }

    // MARK: Вкладки

    func testBrowserTab() async {
        let env = FakeEnvironment()
        _ = await run(env, "browser_tab", ["action": "new_tab", "browser": "chrome"])
        XCTAssertEqual(env.browser.tabActions.first?.0, .newTab)
        XCTAssertEqual(env.browser.tabActions.first?.1, .chrome)
        let bad = await run(env, "browser_tab", ["action": "close_all", "browser": "safari"])
        XCTAssertTrue(bad.result.isError)
    }

    // MARK: Продуктивность

    func testDateTime() async throws {
        let env = FakeEnvironment()
        let record = await run(env, "get_date_time")
        let value = try json(record)
        XCTAssertEqual(value["date"]?.stringValue, "2026-03-15")
        XCTAssertEqual(value["time"]?.stringValue, "14:05")
        XCTAssertEqual(value["weekday"]?.stringValue, "Sunday")
        XCTAssertEqual(value["time_zone"]?.stringValue, "UTC")
    }

    func testTimerBoundsAndDefaultLabel() async throws {
        let env = FakeEnvironment()
        let ok = await run(env, "set_timer", ["minutes": 10])
        XCTAssertFalse(ok.result.isError, ok.result.content)
        XCTAssertEqual(env.productivity.timers.first?.0, 10)
        XCTAssertEqual(env.productivity.timers.first?.1, "Время вышло")
        let tooShort = await run(env, "set_timer", ["minutes": 0])
        XCTAssertTrue(tooShort.result.isError)
        let tooLong = await run(env, "set_timer", ["minutes": 2000])
        XCTAssertTrue(tooLong.result.isError)
        XCTAssertEqual(env.productivity.timers.count, 1)
    }

    func testCreateReminder() async {
        let env = FakeEnvironment()
        _ = await run(env, "create_reminder", ["title": "Купить молоко"])
        XCTAssertEqual(env.productivity.reminders, ["Купить молоко"])
    }

    // MARK: Система

    func testOpenFolderScreenshotDarkModeSleep() async throws {
        let env = FakeEnvironment()
        _ = await run(env, "open_folder", ["folder": "downloads"])
        XCTAssertEqual(env.system.openedFolders, [.downloads])
        let badFolder = await run(env, "open_folder", ["folder": "/etc"])
        XCTAssertTrue(badFolder.result.isError)

        let shot = await run(env, "take_screenshot")
        XCTAssertEqual(try json(shot)["location"]?.stringValue, "Desktop")
        XCTAssertEqual(env.system.screenshots, 1)

        _ = await run(env, "set_dark_mode", ["enabled": true])
        XCTAssertTrue(env.system.darkMode)
        _ = await run(env, "sleep_display")
        XCTAssertTrue(env.system.displaySleeping)
    }

    // MARK: Приложения и окна

    func testHideApplicationAndWindowAction() async {
        let env = FakeEnvironment()
        _ = await run(env, "hide_application", ["name": "Safari"])
        XCTAssertEqual(env.apps.hidden, ["Safari"])

        _ = await run(env, "window_action", ["action": "exit_fullscreen"])
        XCTAssertEqual(env.windows.windowActions.first?.0, .exitFullscreen)
        XCTAssertNil(env.windows.windowActions.first?.1 ?? nil)

        env.windows.isAccessibilityTrusted = false
        let denied = await run(env, "window_action", ["action": "minimize"])
        XCTAssertTrue(denied.result.isError)
    }

    // MARK: Поиск

    func testNewSearchEngines() throws {
        let wiki = try XCTUnwrap(WebURLBuilder.searchURL(engine: "wikipedia", query: "Swift", language: .ukrainian))
        XCTAssertEqual(wiki.host, "uk.wikipedia.org")
        let translate = try XCTUnwrap(WebURLBuilder.searchURL(engine: "translate", query: "hello", language: .german))
        let items = URLComponents(url: translate, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "tl", value: "de")))
        XCTAssertEqual(WebURLBuilder.searchURL(engine: "images", query: "кот")?.host, "www.google.com")
        XCTAssertNotNil(WebURLBuilder.searchURL(engine: "maps", query: "кафе рядом"))
    }

    func testWebSearchUsesSettingsLanguageForWikipedia() async throws {
        var env = FakeEnvironment()
        env.settings.language = .german
        _ = await run(env, "web_search", ["engine": "wikipedia", "query": "Berlin"])
        XCTAssertEqual(env.browser.opened.first?.0.host, "de.wikipedia.org")
    }
}
