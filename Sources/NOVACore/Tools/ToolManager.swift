import Foundation

/// Вызов инструмента, пришедший от модели (`tool_use`).
public struct ToolCall: Sendable, Equatable {
    public let id: String
    public let name: String
    public let input: JSONValue

    public init(id: String, name: String, input: JSONValue) {
        self.id = id
        self.name = name
        self.input = input
    }
}

/// Результат для отправки обратно модели (`tool_result`).
public struct ToolResult: Sendable, Equatable {
    public let toolUseID: String
    public let content: String
    public let isError: Bool

    public init(toolUseID: String, content: String, isError: Bool) {
        self.toolUseID = toolUseID
        self.content = content
        self.isError = isError
    }

    public var apiBlock: JSONValue {
        var block: [String: JSONValue] = [
            "type": "tool_result",
            "tool_use_id": .string(toolUseID),
            "content": .string(content)
        ]
        if isError { block["is_error"] = true }
        return .object(block)
    }
}

/// Запрос подтверждения опасного действия.
public struct ConfirmationRequest: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let tool: ToolName
    public let prompt: String

    public init(id: UUID = UUID(), tool: ToolName, prompt: String) {
        self.id = id
        self.tool = tool
        self.prompt = prompt
    }
}

@MainActor
public protocol ConfirmationProviding: AnyObject {
    /// Возвращает true, только если пользователь явно подтвердил действие.
    func requestConfirmation(_ request: ConfirmationRequest) async -> Bool
}

/// Обработчик инструмента: получает уже проверенные аргументы.
public typealias ToolHandler = @MainActor (ValidatedArguments) async throws -> String

/// Запись о выполненном действии (для истории команд и UI).
public struct ToolExecutionRecord: Sendable, Equatable {
    public let tool: String
    public let arguments: String
    public let result: ToolResult
}

/// Единственная точка выполнения инструментов:
/// белый список → валидация аргументов → подтверждение (если нужно) → обработчик.
@MainActor
public final class ToolManager {
    private let validator = ToolArgumentValidator()
    private var handlers: [ToolName: ToolHandler]
    public weak var confirmationProvider: ConfirmationProviding?
    public var language: () -> SupportedLanguage

    public init(
        handlers: [ToolName: ToolHandler],
        confirmationProvider: ConfirmationProviding? = nil,
        language: @escaping () -> SupportedLanguage = { .russian }
    ) {
        self.handlers = handlers
        self.confirmationProvider = confirmationProvider
        self.language = language
    }

    /// Инструменты, для которых есть обработчик (только они отправляются модели).
    public var availableDefinitions: [ToolDefinition] {
        ToolCatalog.all.filter { handlers[$0.name] != nil }
    }

    public func execute(_ call: ToolCall) async -> ToolExecutionRecord {
        let argumentsText = call.input.compactString()
        func record(_ content: String, isError: Bool) -> ToolExecutionRecord {
            ToolExecutionRecord(
                tool: call.name,
                arguments: argumentsText,
                result: ToolResult(toolUseID: call.id, content: content, isError: isError)
            )
        }

        // 1. Белый список + 2. валидация.
        let arguments: ValidatedArguments
        do {
            arguments = try validator.validate(toolName: call.name, input: call.input)
        } catch {
            return record(Self.describe(error), isError: true)
        }
        guard let handler = handlers[arguments.tool] else {
            return record(ToolValidationError.unknownTool(call.name).errorDescription ?? "Unknown tool", isError: true)
        }

        // 3. Подтверждение опасных действий. Без провайдера — отказ (fail closed).
        let definition = ToolCatalog.definition(for: arguments.tool)
        if definition.risk == .requiresConfirmation {
            let prompt = ConfirmationText.prompt(for: arguments, language: language())
            let request = ConfirmationRequest(tool: arguments.tool, prompt: prompt)
            let approved = await confirmationProvider?.requestConfirmation(request) ?? false
            guard approved else {
                return record(AutomationError.cancelledByUser.errorDescription ?? "Declined", isError: true)
            }
        }

        // 4. Выполнение.
        do {
            let output = try await handler(arguments)
            return record(output, isError: false)
        } catch {
            return record(Self.describe(error), isError: true)
        }
    }

    static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}

/// Тексты подтверждений на языке пользователя.
public enum ConfirmationText {
    public static func prompt(for arguments: ValidatedArguments, language: SupportedLanguage) -> String {
        switch arguments.tool {
        case .quitApplication:
            let name = arguments.string("name") ?? "?"
            switch language {
            case .russian: return "Закрыть приложение «\(name)»? Несохранённые данные могут быть потеряны."
            case .ukrainian: return "Закрити застосунок «\(name)»? Незбережені дані можуть бути втрачені."
            case .english: return "Quit \(name)? Unsaved changes may be lost."
            case .german: return "\(name) beenden? Nicht gespeicherte Änderungen können verloren gehen."
            }
        default:
            let action = arguments.tool.rawValue
            switch language {
            case .russian: return "Выполнить действие «\(action)»?"
            case .ukrainian: return "Виконати дію «\(action)»?"
            case .english: return "Perform action “\(action)”?"
            case .german: return "Aktion „\(action)“ ausführen?"
            }
        }
    }
}
