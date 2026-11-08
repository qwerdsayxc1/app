import Foundation

/// Постоянное хранилище памяти (SwiftData в приложении, in-memory в тестах).
@MainActor
public protocol MemoryStore: AnyObject {
    /// Последние `limit` сообщений в хронологическом порядке.
    func fetchMessages(limit: Int) -> [ChatMessage]
    func insert(_ message: ChatMessage)
    /// Последние `limit` команд, новые первыми.
    func fetchCommands(limit: Int) -> [CommandRecord]
    func insert(_ command: CommandRecord)
    func messageCount() -> Int
    func commandCount() -> Int
    /// Удаляет самые старые записи сверх лимита.
    func prune(keepingMessages: Int, keepingCommands: Int)
    func removeAll()
}

/// Память ассистента: история диалога, последние команды, контекст разговора.
@MainActor
public final class MemoryManager {
    private let store: MemoryStore
    public let maxStoredMessages: Int
    public let maxStoredCommands: Int

    public init(store: MemoryStore, maxStoredMessages: Int = 500, maxStoredCommands: Int = 200) {
        self.store = store
        self.maxStoredMessages = max(2, maxStoredMessages)
        self.maxStoredCommands = max(1, maxStoredCommands)
    }

    /// Сохраняет обмен репликами и выполненную команду.
    public func recordExchange(utterance: String, reply: String, actions: [String], succeeded: Bool, date: Date = Date()) {
        let trimmedUtterance = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUtterance.isEmpty else { return }
        store.insert(ChatMessage(role: .user, text: trimmedUtterance, date: date))
        let trimmedReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedReply.isEmpty {
            store.insert(ChatMessage(role: .assistant, text: trimmedReply, date: date.addingTimeInterval(0.001)))
        }
        store.insert(CommandRecord(utterance: trimmedUtterance, actions: actions, summary: trimmedReply, succeeded: succeeded, date: date))
        enforceLimits()
    }

    /// Контекст разговора для модели: последние `turnLimit` реплик.
    public func conversationContext(turnLimit: Int) -> [ChatMessage] {
        store.fetchMessages(limit: max(0, turnLimit))
    }

    public func history(limit: Int = 100) -> [ChatMessage] {
        store.fetchMessages(limit: limit)
    }

    public func recentCommands(limit: Int = 20) -> [CommandRecord] {
        store.fetchCommands(limit: limit)
    }

    public func clearAll() {
        store.removeAll()
    }

    private func enforceLimits() {
        if store.messageCount() > maxStoredMessages || store.commandCount() > maxStoredCommands {
            store.prune(keepingMessages: maxStoredMessages, keepingCommands: maxStoredCommands)
        }
    }
}

/// Хранилище в памяти процесса (тесты, превью, запасной вариант, если SwiftData недоступна).
@MainActor
public final class InMemoryMemoryStore: MemoryStore {
    private var messages: [ChatMessage] = []
    private var commands: [CommandRecord] = []

    public init() {}

    public func fetchMessages(limit: Int) -> [ChatMessage] {
        Array(messages.sorted { $0.date < $1.date }.suffix(max(0, limit)))
    }

    public func insert(_ message: ChatMessage) {
        messages.append(message)
    }

    public func fetchCommands(limit: Int) -> [CommandRecord] {
        Array(commands.sorted { $0.date > $1.date }.prefix(max(0, limit)))
    }

    public func insert(_ command: CommandRecord) {
        commands.append(command)
    }

    public func messageCount() -> Int { messages.count }
    public func commandCount() -> Int { commands.count }

    public func prune(keepingMessages: Int, keepingCommands: Int) {
        messages = Array(messages.sorted { $0.date < $1.date }.suffix(keepingMessages))
        commands = Array(commands.sorted { $0.date < $1.date }.suffix(keepingCommands))
    }

    public func removeAll() {
        messages.removeAll()
        commands.removeAll()
    }
}
