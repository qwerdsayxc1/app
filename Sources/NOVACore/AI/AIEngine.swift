import Foundation

/// События обработки для обновления статуса в UI.
public enum AIEngineEvent: Sendable, Equatable {
    case thinking
    case executing(tool: String)
    case toolFinished(tool: String, success: Bool)
}

public struct AIEngineResult: Sendable, Equatable {
    public let reply: String
    public let actions: [ToolExecutionRecord]

    public var succeeded: Bool { actions.allSatisfy { !$0.result.isError } }

    /// Краткое описание действий для истории команд.
    public var actionSummaries: [String] {
        actions.map { action in
            let mark = action.result.isError ? "✗" : "✓"
            return "\(mark) \(action.tool) \(action.arguments)"
        }
    }
}

public enum AIEngineError: Error, Equatable, Sendable, LocalizedError {
    case consentRequired
    case emptyUtterance
    case refused(category: String?)
    case toolRoundLimitReached
    case truncated

    public var errorDescription: String? {
        switch self {
        case .consentRequired:
            return "Чтобы обрабатывать команды, NOVA отправляет распознанный текст в Claude API. Разрешите это в настройках."
        case .emptyUtterance:
            return "Команда не распознана."
        case .refused:
            return "Claude отказался выполнять этот запрос."
        case .toolRoundLimitReached:
            return "Слишком много шагов для одной команды — остановлено."
        case .truncated:
            return "Ответ модели оборвался. Попробуйте сформулировать короче."
        }
    }
}

/// «Мозг» ассистента: агентный цикл Claude ↔ инструменты.
///
/// 1. Добавляет фразу пользователя в историю.
/// 2. Отправляет историю, системный промпт и белый список инструментов в Claude.
/// 3. Пока `stop_reason == tool_use`: выполняет ВСЕ вызовы хода через ToolManager
///    (валидация, подтверждение) и возвращает результаты одним сообщением.
/// 4. Возвращает итоговый текст и список выполненных действий.
@MainActor
public final class AIEngine {
    private let claude: ClaudeMessaging
    private let toolManager: ToolManager
    private let settings: () -> AppSettings
    private let maxToolRounds: Int
    public private(set) var context = ConversationContext()

    public init(
        claude: ClaudeMessaging,
        toolManager: ToolManager,
        settings: @escaping () -> AppSettings,
        maxToolRounds: Int = 8
    ) {
        self.claude = claude
        self.toolManager = toolManager
        self.settings = settings
        self.maxToolRounds = maxToolRounds
    }

    /// Сбрасывает контекст текущей сессии (например, при очистке памяти).
    public func resetConversation() {
        context.reset()
    }

    public func process(
        _ utterance: String,
        history: [ChatMessage],
        onEvent: @MainActor (AIEngineEvent) -> Void = { _ in }
    ) async throws -> AIEngineResult {
        let text = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIEngineError.emptyUtterance }

        let currentSettings = settings()
        guard currentSettings.cloudProcessingConsent else { throw AIEngineError.consentRequired }

        // Новая сессия или слишком длинная история → пересоздать из памяти (без правки старых блоков).
        if context.isEmpty || context.userTurnCount >= currentSettings.contextTurnLimit {
            context.reseed(from: history, limit: max(0, currentSettings.contextTurnLimit - 1))
        }

        let checkpoint = context.checkpoint
        context.appendUser(text)

        var configuration = ClaudeConfiguration()
        configuration.model = currentSettings.model
        configuration.effort = currentSettings.effort

        let system = SystemPrompt.make(language: currentSettings.language)
        let tools = toolManager.availableDefinitions
        var actions: [ToolExecutionRecord] = []

        do {
            for _ in 0..<maxToolRounds {
                try Task.checkCancellation()
                onEvent(.thinking)
                let response = try await claude.send(
                    system: system,
                    messages: context.messages,
                    tools: tools,
                    configuration: configuration
                )
                try Task.checkCancellation()

                switch response.stopReason {
                case .refusal(let category):
                    throw AIEngineError.refused(category: category)
                case .maxTokens:
                    throw AIEngineError.truncated
                default:
                    break
                }

                context.appendAssistant(rawContent: response.rawContent)

                if response.stopReason == .toolUse, !response.toolCalls.isEmpty {
                    var results: [ToolResult] = []
                    for call in response.toolCalls {
                        try Task.checkCancellation()
                        onEvent(.executing(tool: call.name))
                        let record = await toolManager.execute(call)
                        actions.append(record)
                        results.append(record.result)
                        onEvent(.toolFinished(tool: call.name, success: !record.result.isError))
                    }
                    context.appendToolResults(results)
                    continue
                }

                if response.stopReason == .pauseTurn {
                    // Сервер приостановил ход — продолжаем тем же запросом.
                    continue
                }

                return AIEngineResult(reply: response.text, actions: actions)
            }
            throw AIEngineError.toolRoundLimitReached
        } catch {
            // Незавершённый ход (tool_use без tool_result и т.п.) убираем из хвоста,
            // иначе следующий запрос получит 400.
            context.rollback(to: checkpoint)
            if error is CancellationError { throw ClaudeAPIError.cancelled }
            throw error
        }
    }
}
