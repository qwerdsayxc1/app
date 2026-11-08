import Foundation

/// Причина остановки генерации (`stop_reason`).
public enum StopReason: Sendable, Equatable {
    case endTurn
    case toolUse
    case maxTokens
    case stopSequence
    case pauseTurn
    case refusal(category: String?)
    case other(String)

    init(raw: String?, stopDetails: JSONValue?) {
        switch raw {
        case "end_turn": self = .endTurn
        case "tool_use": self = .toolUse
        case "max_tokens": self = .maxTokens
        case "stop_sequence": self = .stopSequence
        case "pause_turn": self = .pauseTurn
        case "refusal": self = .refusal(category: stopDetails?["category"]?.stringValue)
        case .some(let value): self = .other(value)
        case .none: self = .other("unknown")
        }
    }
}

/// Разобранный ответ Messages API.
public struct ClaudeResponse: Sendable, Equatable {
    public let id: String
    public let model: String
    public let stopReason: StopReason
    /// Исходные блоки контента — возвращаются в историю БЕЗ изменений
    /// (thinking-блоки, fallback-блоки и т.д. должны сохраняться как есть).
    public let rawContent: [JSONValue]
    /// Объединённый видимый текст ответа.
    public let text: String
    public let toolCalls: [ToolCall]
    public let usage: Usage

    public struct Usage: Sendable, Equatable {
        public let inputTokens: Int
        public let outputTokens: Int
        public let cacheReadInputTokens: Int
        public let cacheCreationInputTokens: Int
    }
}

/// Конфигурация клиента Claude.
public struct ClaudeConfiguration: Sendable, Equatable {
    public var model: ClaudeModelChoice
    public var effort: ReasoningEffort
    public var maxTokens: Int
    public var endpoint: URL
    public var apiVersion: String
    /// Серверный fallback при `refusal` (beta `server-side-fallback-2026-07-01`, `fallbacks: "default"`).
    public var useServerSideFallback: Bool
    public var requestTimeout: TimeInterval
    public var maxRetries: Int

    public init(
        model: ClaudeModelChoice = .opus,
        effort: ReasoningEffort = .low,
        maxTokens: Int = 16_000,
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        apiVersion: String = "2026-10-21",
        useServerSideFallback: Bool = true,
        requestTimeout: TimeInterval = 120,
        maxRetries: Int = 2
    ) {
        self.model = model
        self.effort = effort
        self.maxTokens = maxTokens
        self.endpoint = endpoint
        self.apiVersion = apiVersion
        self.useServerSideFallback = useServerSideFallback
        self.requestTimeout = requestTimeout
        self.maxRetries = maxRetries
    }

    public static let serverSideFallbackBeta = "server-side-fallback-2026-07-01"
}

/// Ошибки обращения к Claude API.
public enum ClaudeAPIError: Error, Equatable, Sendable, LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case permissionDenied(String)
    case rateLimited(retryAfter: TimeInterval?)
    case overloaded
    case badRequest(String)
    case server(status: Int, message: String)
    case network(String)
    case invalidResponse(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "API-ключ Anthropic не задан. Добавьте его в настройках."
        case .invalidAPIKey: return "API-ключ Anthropic недействителен (401)."
        case .permissionDenied(let message): return "Доступ запрещён: \(message)"
        case .rateLimited: return "Превышен лимит запросов к Claude. Попробуйте чуть позже."
        case .overloaded: return "Claude API перегружен. Попробуйте чуть позже."
        case .badRequest(let message): return "Некорректный запрос к Claude: \(message)"
        case let .server(status, message): return "Ошибка сервера Claude (\(status)): \(message)"
        case .network(let message): return "Нет связи с Claude API: \(message)"
        case .invalidResponse(let message): return "Неожиданный ответ Claude API: \(message)"
        case .cancelled: return "Запрос отменён."
        }
    }

    /// Можно ли повторить запрос.
    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .overloaded, .network: return true
        case .server(let status, _): return status >= 500
        default: return false
        }
    }
}
