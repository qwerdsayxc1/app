import Foundation

/// История сообщений для Messages API в рамках текущей сессии.
///
/// История ведётся строго в режиме append-only: блоки ассистента (включая thinking)
/// возвращаются без изменений. Когда история слишком длинная, она не редактируется,
/// а пересоздаётся целиком из текстовых реплик памяти (без thinking-блоков) —
/// так не нарушается проверка «preserved thinking» на моделях Opus 5.5 / Sonnet 5.5.
public struct ConversationContext: Sendable, Equatable {
    public private(set) var messages: [JSONValue] = []
    public private(set) var userTurnCount = 0

    public init() {}

    public var isEmpty: Bool { messages.isEmpty }

    /// Контрольная точка для отката незавершённого хода (ошибка, отмена).
    public var checkpoint: Int { messages.count }

    public mutating func rollback(to checkpoint: Int) {
        guard checkpoint >= 0, checkpoint < messages.count else { return }
        let removed = messages[checkpoint...]
        let removedUserTurns = removed.filter(Self.isUserTextMessage).count
        messages.removeSubrange(checkpoint...)
        userTurnCount = max(0, userTurnCount - removedUserTurns)
    }

    public mutating func appendUser(_ text: String) {
        messages.append(["role": "user", "content": .string(text)])
        userTurnCount += 1
    }

    public mutating func appendAssistant(rawContent: [JSONValue]) {
        messages.append(["role": "assistant", "content": .array(rawContent)])
    }

    /// Все результаты инструментов одного хода — одним user-сообщением.
    public mutating func appendToolResults(_ results: [ToolResult]) {
        guard !results.isEmpty else { return }
        messages.append(["role": "user", "content": .array(results.map(\.apiBlock))])
    }

    public mutating func reset() {
        messages.removeAll()
        userTurnCount = 0
    }

    /// Пересоздаёт историю из текстовых реплик (последние `limit`).
    /// Первое сообщение обязано быть от пользователя.
    public mutating func reseed(from history: [ChatMessage], limit: Int) {
        reset()
        var recent = Array(history.suffix(max(0, limit)))
        while let first = recent.first, first.role != .user {
            recent.removeFirst()
        }
        for message in recent {
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            switch message.role {
            case .user:
                appendUser(text)
            case .assistant:
                messages.append(["role": "assistant", "content": .string(text)])
            }
        }
    }

    private static func isUserTextMessage(_ message: JSONValue) -> Bool {
        message["role"]?.stringValue == "user" && message["content"]?.stringValue != nil
    }
}
