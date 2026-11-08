import Foundation
import SwiftData
import NOVACore

@Model
final class StoredMessage {
    @Attribute(.unique) var id: UUID
    var role: String
    var text: String
    var date: Date

    init(id: UUID, role: String, text: String, date: Date) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
    }
}

@Model
final class StoredCommand {
    @Attribute(.unique) var id: UUID
    var utterance: String
    var actions: [String]
    var summary: String
    var succeeded: Bool
    var date: Date

    init(id: UUID, utterance: String, actions: [String], summary: String, succeeded: Bool, date: Date) {
        self.id = id
        self.utterance = utterance
        self.actions = actions
        self.summary = summary
        self.succeeded = succeeded
        self.date = date
    }
}

/// Постоянная память на SwiftData (локально, в контейнере приложения; никуда не синхронизируется).
@MainActor
final class SwiftDataMemoryStore: MemoryStore {
    private let context: ModelContext

    init(container: ModelContainer) {
        self.context = container.mainContext
    }

    static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration("NOVAMemory", cloudKitDatabase: .none)
        return try ModelContainer(for: StoredMessage.self, StoredCommand.self, configurations: configuration)
    }

    func fetchMessages(limit: Int) -> [ChatMessage] {
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<StoredMessage>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        let stored = (try? context.fetch(descriptor)) ?? []
        return stored.reversed().compactMap { item in
            guard let role = ChatMessage.Role(rawValue: item.role) else { return nil }
            return ChatMessage(id: item.id, role: role, text: item.text, date: item.date)
        }
    }

    func insert(_ message: ChatMessage) {
        context.insert(StoredMessage(id: message.id, role: message.role.rawValue, text: message.text, date: message.date))
        save()
    }

    func fetchCommands(limit: Int) -> [CommandRecord] {
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<StoredCommand>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        let stored = (try? context.fetch(descriptor)) ?? []
        return stored.map {
            CommandRecord(id: $0.id, utterance: $0.utterance, actions: $0.actions, summary: $0.summary, succeeded: $0.succeeded, date: $0.date)
        }
    }

    func insert(_ command: CommandRecord) {
        context.insert(StoredCommand(
            id: command.id,
            utterance: command.utterance,
            actions: command.actions,
            summary: command.summary,
            succeeded: command.succeeded,
            date: command.date
        ))
        save()
    }

    func messageCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<StoredMessage>())) ?? 0
    }

    func commandCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<StoredCommand>())) ?? 0
    }

    func prune(keepingMessages: Int, keepingCommands: Int) {
        let messages = (try? context.fetch(FetchDescriptor<StoredMessage>(sortBy: [SortDescriptor(\.date, order: .forward)]))) ?? []
        for message in messages.dropLast(max(0, keepingMessages)) {
            context.delete(message)
        }
        let commands = (try? context.fetch(FetchDescriptor<StoredCommand>(sortBy: [SortDescriptor(\.date, order: .forward)]))) ?? []
        for command in commands.dropLast(max(0, keepingCommands)) {
            context.delete(command)
        }
        save()
    }

    func removeAll() {
        try? context.delete(model: StoredMessage.self)
        try? context.delete(model: StoredCommand.self)
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            NSLog("NOVA: SwiftData save failed: %@", error.localizedDescription)
        }
    }
}
