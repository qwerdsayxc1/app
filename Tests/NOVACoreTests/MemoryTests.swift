import XCTest
@testable import NOVACore

@MainActor
final class MemoryTests: XCTestCase {
    func testRecordExchangeStoresMessagesAndCommand() {
        let memory = MemoryManager(store: InMemoryMemoryStore())
        let now = Date()
        memory.recordExchange(utterance: " Открой YouTube ", reply: "Открыл YouTube.", actions: ["✓ open_website"], succeeded: true, date: now)

        let history = memory.history()
        XCTAssertEqual(history.map(\.role), [.user, .assistant])
        XCTAssertEqual(history.first?.text, "Открой YouTube")
        let commands = memory.recentCommands()
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands.first?.utterance, "Открой YouTube")
        XCTAssertEqual(commands.first?.actions, ["✓ open_website"])
        XCTAssertTrue(commands.first?.succeeded ?? false)
    }

    func testEmptyUtteranceIsIgnored() {
        let memory = MemoryManager(store: InMemoryMemoryStore())
        memory.recordExchange(utterance: "   ", reply: "x", actions: [], succeeded: true)
        XCTAssertTrue(memory.history().isEmpty)
        XCTAssertTrue(memory.recentCommands().isEmpty)
    }

    func testEmptyReplyStoresOnlyUserMessage() {
        let memory = MemoryManager(store: InMemoryMemoryStore())
        memory.recordExchange(utterance: "Выключи звук", reply: "", actions: ["✓ set_mute"], succeeded: true)
        XCTAssertEqual(memory.history().map(\.role), [.user])
    }

    func testConversationContextReturnsLatestInOrder() {
        let memory = MemoryManager(store: InMemoryMemoryStore())
        let base = Date(timeIntervalSince1970: 1_000)
        for index in 0..<5 {
            memory.recordExchange(utterance: "q\(index)", reply: "a\(index)", actions: [], succeeded: true, date: base.addingTimeInterval(Double(index)))
        }
        let context = memory.conversationContext(turnLimit: 4)
        XCTAssertEqual(context.map(\.text), ["q3", "a3", "q4", "a4"])
    }

    func testRecentCommandsNewestFirst() {
        let memory = MemoryManager(store: InMemoryMemoryStore())
        let base = Date(timeIntervalSince1970: 1_000)
        memory.recordExchange(utterance: "old", reply: "", actions: [], succeeded: true, date: base)
        memory.recordExchange(utterance: "new", reply: "", actions: [], succeeded: false, date: base.addingTimeInterval(10))
        XCTAssertEqual(memory.recentCommands().map(\.utterance), ["new", "old"])
        XCTAssertEqual(memory.recentCommands(limit: 1).map(\.utterance), ["new"])
    }

    func testPruningKeepsNewest() {
        let store = InMemoryMemoryStore()
        let memory = MemoryManager(store: store, maxStoredMessages: 4, maxStoredCommands: 2)
        let base = Date(timeIntervalSince1970: 1_000)
        for index in 0..<6 {
            memory.recordExchange(utterance: "q\(index)", reply: "a\(index)", actions: [], succeeded: true, date: base.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(store.messageCount(), 4)
        XCTAssertEqual(store.commandCount(), 2)
        XCTAssertEqual(memory.history().map(\.text), ["q4", "a4", "q5", "a5"])
        XCTAssertEqual(memory.recentCommands().map(\.utterance), ["q5", "q4"])
    }

    func testClearAll() {
        let memory = MemoryManager(store: InMemoryMemoryStore())
        memory.recordExchange(utterance: "Привет", reply: "Привет!", actions: [], succeeded: true)
        memory.clearAll()
        XCTAssertTrue(memory.history().isEmpty)
        XCTAssertTrue(memory.recentCommands().isEmpty)
    }

    // MARK: ConversationContext

    func testContextReseedSkipsLeadingAssistantAndBlankMessages() {
        var context = ConversationContext()
        context.reseed(from: [
            ChatMessage(role: .assistant, text: "orphan"),
            ChatMessage(role: .user, text: "  "),
            ChatMessage(role: .user, text: "q1"),
            ChatMessage(role: .assistant, text: "a1")
        ], limit: 10)
        XCTAssertEqual(context.messages.map { $0["content"]?.stringValue }, ["q1", "a1"])
        XCTAssertEqual(context.userTurnCount, 1)
    }

    func testContextRollback() {
        var context = ConversationContext()
        context.appendUser("q1")
        context.appendAssistant(rawContent: [["type": "text", "text": "a1"]])
        let checkpoint = context.checkpoint
        context.appendUser("q2")
        context.appendAssistant(rawContent: [["type": "tool_use", "id": "t", "name": "get_volume", "input": [:]]])
        context.rollback(to: checkpoint)
        XCTAssertEqual(context.messages.count, 2)
        XCTAssertEqual(context.userTurnCount, 1)
        context.rollback(to: 99)
        XCTAssertEqual(context.messages.count, 2, "некорректная точка отката игнорируется")
    }

    func testToolResultsGoInSingleUserMessage() {
        var context = ConversationContext()
        context.appendToolResults([
            ToolResult(toolUseID: "a", content: "1", isError: false),
            ToolResult(toolUseID: "b", content: "2", isError: true)
        ])
        XCTAssertEqual(context.messages.count, 1)
        XCTAssertEqual(context.messages[0]["content"]?.arrayValue?.count, 2)
        context.appendToolResults([])
        XCTAssertEqual(context.messages.count, 1)
    }
}
