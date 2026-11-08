import XCTest
@testable import NOVACore

@MainActor
final class AIEngineTests: XCTestCase {
    private func makeEngine(_ claude: ScriptedClaude, env: FakeEnvironment, confirmation: ConfirmationProviding? = nil) -> AIEngine {
        let settings = env.settings
        return AIEngine(claude: claude, toolManager: env.toolManager(confirmation: confirmation), settings: { settings })
    }

    func testSimpleAnswerWithoutTools() async throws {
        let claude = ScriptedClaude([messageJSON(content: [textBlock("Привет!")], stopReason: "end_turn")])
        let engine = makeEngine(claude, env: FakeEnvironment())
        let result = try await engine.process("Привет", history: [])
        XCTAssertEqual(result.reply, "Привет!")
        XCTAssertTrue(result.actions.isEmpty)
    }

    func testMultiStepToolLoop() async throws {
        // «Открой Safari и перейди на сайт Apple, потом сделай громче на 20%»
        let claude = ScriptedClaude([
            messageJSON(content: [
                thinkingBlock(),
                toolUseBlock(id: "toolu_1", name: "open_url", input: ["url": "https://www.apple.com", "browser": "safari"]),
                toolUseBlock(id: "toolu_2", name: "change_volume", input: ["delta": 20])
            ], stopReason: "tool_use"),
            messageJSON(content: [textBlock("Открыл сайт Apple в Safari и сделал громче.")], stopReason: "end_turn")
        ])
        let env = FakeEnvironment()
        let engine = makeEngine(claude, env: env)
        var events: [AIEngineEvent] = []
        let result = try await engine.process("Открой Safari и перейди на сайт Apple, и громче на 20%", history: []) { events.append($0) }

        XCTAssertEqual(result.actions.map(\.tool), ["open_url", "change_volume"])
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(env.browser.opened.first?.0.absoluteString, "https://www.apple.com")
        XCTAssertEqual(env.system.level, 70)
        XCTAssertEqual(events.first, .thinking)
        XCTAssertTrue(events.contains(.executing(tool: "open_url")))

        // Второй запрос: assistant-блоки (включая thinking) без изменений + все tool_result одним сообщением.
        XCTAssertEqual(claude.callCount, 2)
        let second = claude.receivedMessages[1]
        XCTAssertEqual(second.count, 3)
        XCTAssertEqual(second[1]["content"]?.arrayValue?.first?["type"]?.stringValue, "thinking")
        let toolResults = try XCTUnwrap(second[2]["content"]?.arrayValue)
        XCTAssertEqual(toolResults.map { $0["tool_use_id"]?.stringValue }, ["toolu_1", "toolu_2"])
        XCTAssertEqual(second[2]["role"]?.stringValue, "user")
    }

    func testInvalidToolCallIsReportedBackToModel() async throws {
        let claude = ScriptedClaude([
            messageJSON(content: [toolUseBlock(id: "toolu_1", name: "delete_file", input: ["path": "/"])], stopReason: "tool_use"),
            messageJSON(content: [textBlock("Я не умею удалять файлы.")], stopReason: "end_turn")
        ])
        let engine = makeEngine(claude, env: FakeEnvironment())
        let result = try await engine.process("Удали всё", history: [])
        XCTAssertFalse(result.succeeded)
        let resultBlock = try XCTUnwrap(claude.receivedMessages[1].last?["content"]?.arrayValue?.first)
        XCTAssertEqual(resultBlock["is_error"]?.boolValue, true)
    }

    func testConsentIsRequired() async {
        var env = FakeEnvironment()
        env.settings.cloudProcessingConsent = false
        let claude = ScriptedClaude([])
        let engine = makeEngine(claude, env: env)
        do {
            _ = try await engine.process("Открой YouTube", history: [])
            XCTFail("ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? AIEngineError, .consentRequired)
            XCTAssertEqual(claude.callCount, 0, "без согласия ничего не отправляется")
        }
    }

    func testEmptyUtteranceRejected() async {
        let engine = makeEngine(ScriptedClaude([]), env: FakeEnvironment())
        do {
            _ = try await engine.process("   ", history: [])
            XCTFail("ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? AIEngineError, .emptyUtterance)
        }
    }

    func testRefusalRollsBackContext() async throws {
        let claude = ScriptedClaude([
            messageJSON(content: [], stopReason: "refusal", stopDetails: ["category": "cyber"]),
            messageJSON(content: [textBlock("Ок")], stopReason: "end_turn")
        ])
        let engine = makeEngine(claude, env: FakeEnvironment())
        do {
            _ = try await engine.process("плохой запрос", history: [])
            XCTFail("ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? AIEngineError, .refused(category: "cyber"))
        }
        XCTAssertTrue(engine.context.isEmpty)
        _ = try await engine.process("Привет", history: [])
        XCTAssertEqual(claude.receivedMessages[1].count, 1, "отклонённый ход не попадает в историю")
    }

    func testNetworkErrorMidLoopRollsBackIncompleteTurn() async throws {
        let first = try ClaudeResponseParser.parse(messageJSON(content: [toolUseBlock(id: "toolu_1", name: "get_volume", input: [:])], stopReason: "tool_use"))
        let claude = ScriptedClaude(results: [.success(first), .failure(ClaudeAPIError.network("offline"))])
        let engine = makeEngine(claude, env: FakeEnvironment())
        do {
            _ = try await engine.process("Какая громкость?", history: [])
            XCTFail("ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? ClaudeAPIError, .network("offline"))
        }
        XCTAssertTrue(engine.context.isEmpty, "tool_use без tool_result не должен остаться в истории")
    }

    func testToolRoundLimit() async {
        let loop = messageJSON(content: [toolUseBlock(id: "toolu_x", name: "get_volume", input: [:])], stopReason: "tool_use")
        let claude = ScriptedClaude(Array(repeating: loop, count: 10))
        let env = FakeEnvironment()
        let settings = env.settings
        let engine = AIEngine(claude: claude, toolManager: env.toolManager(), settings: { settings }, maxToolRounds: 3)
        do {
            _ = try await engine.process("громкость", history: [])
            XCTFail("ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? AIEngineError, .toolRoundLimitReached)
            XCTAssertEqual(claude.callCount, 3)
        }
    }

    func testHistorySeedsNewSessionAndModelSettingsApplied() async throws {
        var env = FakeEnvironment()
        env.settings.model = .sonnet
        env.settings.effort = .medium
        let claude = ScriptedClaude([messageJSON(content: [textBlock("Да")], stopReason: "end_turn")])
        let engine = makeEngine(claude, env: env)
        let history = [
            ChatMessage(role: .assistant, text: "сирота-ответ без вопроса"),
            ChatMessage(role: .user, text: "Открой YouTube"),
            ChatMessage(role: .assistant, text: "Открыл YouTube.")
        ]
        _ = try await engine.process("А теперь GitHub", history: history)
        let sent = claude.receivedMessages[0]
        XCTAssertEqual(sent.map { $0["role"]?.stringValue }, ["user", "assistant", "user"], "история начинается с user")
        XCTAssertEqual(sent.last?["content"]?.stringValue, "А теперь GitHub")
        XCTAssertEqual(claude.receivedConfigurations[0].model, .sonnet)
        XCTAssertEqual(claude.receivedConfigurations[0].effort, .medium)
        XCTAssertEqual(claude.receivedTools[0].count, ToolCatalog.all.count)
    }

    func testResetConversation() async throws {
        let claude = ScriptedClaude([messageJSON(content: [textBlock("Да")], stopReason: "end_turn")])
        let engine = makeEngine(claude, env: FakeEnvironment())
        _ = try await engine.process("Привет", history: [])
        XCTAssertFalse(engine.context.isEmpty)
        engine.resetConversation()
        XCTAssertTrue(engine.context.isEmpty)
    }
}
