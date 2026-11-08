import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NOVACore

final class ClaudeParsingTests: XCTestCase {
    func testParsesTextAndToolCalls() throws {
        let json = messageJSON(
            content: [
                thinkingBlock(),
                textBlock("Открываю YouTube."),
                toolUseBlock(id: "toolu_1", name: "open_website", input: ["site": "youtube"]),
                toolUseBlock(id: "toolu_2", name: "change_volume", input: ["delta": 20])
            ],
            stopReason: "tool_use"
        )
        let response = try ClaudeResponseParser.parse(json)
        XCTAssertEqual(response.stopReason, .toolUse)
        XCTAssertEqual(response.text, "Открываю YouTube.")
        XCTAssertEqual(response.toolCalls, [
            ToolCall(id: "toolu_1", name: "open_website", input: ["site": "youtube"]),
            ToolCall(id: "toolu_2", name: "change_volume", input: ["delta": 20])
        ])
        XCTAssertEqual(response.rawContent.count, 4, "thinking-блок сохраняется для истории")
        XCTAssertEqual(response.usage.cacheReadInputTokens, 100)
    }

    func testParsesFromRawData() throws {
        let data = Data("""
        {"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5",
         "content":[{"type":"tool_use","id":"toolu_9","name":"set_mute","input":{"muted":true}}],
         "stop_reason":"tool_use","usage":{"input_tokens":5,"output_tokens":7}}
        """.utf8)
        let response = try ClaudeResponseParser.parse(data)
        XCTAssertEqual(response.toolCalls.first?.input["muted"]?.boolValue, true)
        XCTAssertEqual(response.usage.outputTokens, 7)
    }

    func testToolUseWithoutIDIsInvalid() {
        let json = messageJSON(content: [["type": "tool_use", "name": "set_mute", "input": [:]]], stopReason: "tool_use")
        XCTAssertThrowsError(try ClaudeResponseParser.parse(json))
    }

    func testRefusalCategory() throws {
        let json = messageJSON(content: [], stopReason: "refusal", stopDetails: ["type": "refusal", "category": "cyber"])
        XCTAssertEqual(try ClaudeResponseParser.parse(json).stopReason, .refusal(category: "cyber"))
    }

    func testNonJSONBody() {
        XCTAssertThrowsError(try ClaudeResponseParser.parse(Data("<html>".utf8))) { error in
            guard case .invalidResponse? = error as? ClaudeAPIError else { return XCTFail("\(error)") }
        }
    }

    func testHTTPErrorMapping() {
        let body = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"bad tool"}}"#.utf8)
        XCTAssertEqual(ClaudeResponseParser.error(status: 400, data: body, retryAfterHeader: nil), .badRequest("bad tool"))
        XCTAssertEqual(ClaudeResponseParser.error(status: 401, data: body, retryAfterHeader: nil), .invalidAPIKey)
        XCTAssertEqual(ClaudeResponseParser.error(status: 429, data: body, retryAfterHeader: "3"), .rateLimited(retryAfter: 3))
        XCTAssertEqual(ClaudeResponseParser.error(status: 529, data: body, retryAfterHeader: nil), .overloaded)
        XCTAssertTrue(ClaudeAPIError.server(status: 503, message: "").isRetryable)
        XCTAssertFalse(ClaudeAPIError.badRequest("").isRetryable)
    }

    // MARK: Запрос

    func testRequestBodyFollowsCurrentAPIShape() throws {
        let builder = ClaudeRequestBuilder(configuration: ClaudeConfiguration(model: .sonnet, effort: .medium))
        let body = builder.body(system: "sys", messages: [["role": "user", "content": "hi"]], tools: ToolCatalog.all)
        XCTAssertEqual(body["model"]?.stringValue, "claude-sonnet-5-5")
        XCTAssertEqual(body["tool_choice"]?["type"]?.stringValue, "auto")
        XCTAssertEqual(body["output_config"]?["effort"]?.stringValue, "medium")
        XCTAssertEqual(body["fallbacks"]?.stringValue, "default")
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["thinking"], "на Opus/Sonnet 5.5 thinking адаптивный по умолчанию")
        XCTAssertEqual(body["system"]?.arrayValue?.first?["cache_control"]?["type"]?.stringValue, "ephemeral")
        XCTAssertEqual(body["tools"]?.arrayValue?.count, ToolCatalog.all.count)
    }

    func testHeaders() {
        let headers = ClaudeRequestBuilder(configuration: ClaudeConfiguration()).headers(apiKey: "sk-ant-test")
        XCTAssertEqual(headers["x-api-key"], "sk-ant-test")
        XCTAssertEqual(headers["anthropic-version"], "2026-10-21")
        XCTAssertEqual(headers["anthropic-beta"], "server-side-fallback-2026-07-01")
    }

    // MARK: Сервис

    func testServiceRetriesOnOverloadThenSucceeds() async throws {
        let ok = try messageJSON(content: [textBlock("Готово")], stopReason: "end_turn").encodedData()
        let transport = MockTransport([
            .init(status: 529, body: Data(#"{"type":"error","error":{"message":"overloaded"}}"#.utf8), headers: [:]),
            .init(status: 200, body: ok, headers: [:])
        ])
        let service = ClaudeService(transport: transport, apiKeyProvider: { "sk-ant-test-key-123456" }, sleeper: { _ in })
        let response = try await service.send(system: "s", messages: [["role": "user", "content": "hi"]], tools: [], configuration: ClaudeConfiguration())
        XCTAssertEqual(response.text, "Готово")
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test-key-123456")
        XCTAssertEqual(transport.requests.first?.httpMethod, "POST")
    }

    func testServiceDoesNotRetryBadRequest() async {
        let transport = MockTransport([
            .init(status: 400, body: Data(#"{"type":"error","error":{"message":"nope"}}"#.utf8), headers: [:])
        ])
        let service = ClaudeService(transport: transport, apiKeyProvider: { "sk-ant-test-key-123456" }, sleeper: { _ in })
        do {
            _ = try await service.send(system: "s", messages: [], tools: [], configuration: ClaudeConfiguration())
            XCTFail("ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? ClaudeAPIError, .badRequest("nope"))
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testServiceRequiresAPIKey() async {
        let service = ClaudeService(transport: MockTransport([]), apiKeyProvider: { nil }, sleeper: { _ in })
        do {
            _ = try await service.send(system: "s", messages: [], tools: [], configuration: ClaudeConfiguration())
            XCTFail("ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? ClaudeAPIError, .missingAPIKey)
        }
    }

    // MARK: JSONValue

    func testJSONValueRoundTripKeepsIntegers() throws {
        let value: JSONValue = ["a": 20, "b": 1.5, "c": [true, nil, "x"]]
        let text = value.compactString()
        XCTAssertEqual(text, #"{"a":20,"b":1.5,"c":[true,null,"x"]}"#)
        XCTAssertEqual(try JSONValue.decode(from: Data(text.utf8)), value)
    }
}
