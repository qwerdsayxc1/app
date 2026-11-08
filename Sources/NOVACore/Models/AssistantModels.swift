import Foundation

/// Состояние ассистента, отображаемое в UI.
public enum AssistantStatus: String, Sendable, Equatable, CaseIterable {
    case idle
    case listening
    case thinking
    case executing
    case speaking

    public var title: String {
        switch self {
        case .idle: return "Idle"
        case .listening: return "Listening"
        case .thinking: return "Thinking"
        case .executing: return "Executing"
        case .speaking: return "Speaking"
        }
    }
}

/// Поддерживаемые языки распознавания и синтеза речи.
public enum SupportedLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case russian = "ru"
    case ukrainian = "uk"
    case english = "en"
    case german = "de"

    public var id: String { rawValue }

    /// Идентификатор локали для SFSpeechRecognizer / AVSpeechSynthesisVoice.
    public var localeIdentifier: String {
        switch self {
        case .russian: return "ru-RU"
        case .ukrainian: return "uk-UA"
        case .english: return "en-US"
        case .german: return "de-DE"
        }
    }

    public var displayName: String {
        switch self {
        case .russian: return "Русский"
        case .ukrainian: return "Українська"
        case .english: return "English"
        case .german: return "Deutsch"
        }
    }

    /// Название языка для системного промпта (на английском — так модель понимает однозначно).
    public var promptName: String {
        switch self {
        case .russian: return "Russian"
        case .ukrainian: return "Ukrainian"
        case .english: return "English"
        case .german: return "German"
        }
    }
}

/// Реплика диалога (для истории и памяти).
public struct ChatMessage: Sendable, Equatable, Identifiable, Codable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public let id: UUID
    public let role: Role
    public let text: String
    public let date: Date

    public init(id: UUID = UUID(), role: Role, text: String, date: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
    }
}

/// Выполненная команда: фраза пользователя, список действий и итог.
public struct CommandRecord: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    public let utterance: String
    public let actions: [String]
    public let summary: String
    public let succeeded: Bool
    public let date: Date

    public init(
        id: UUID = UUID(),
        utterance: String,
        actions: [String],
        summary: String,
        succeeded: Bool,
        date: Date = Date()
    ) {
        self.id = id
        self.utterance = utterance
        self.actions = actions
        self.summary = summary
        self.succeeded = succeeded
        self.date = date
    }
}
