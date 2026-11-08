import Foundation

/// Ошибки проверки вызова инструмента. Текст уходит обратно модели как `tool_result`
/// с `is_error: true`, чтобы она могла исправить вызов.
public enum ToolValidationError: Error, Equatable, Sendable, LocalizedError {
    case unknownTool(String)
    case argumentsNotObject
    case missingArgument(String)
    case unexpectedArgument(String)
    case typeMismatch(argument: String, expected: String, actual: String)
    case valueNotAllowed(argument: String, value: String, allowed: [String])
    case emptyString(argument: String)
    case stringTooLong(argument: String, maxLength: Int)
    case controlCharacters(argument: String)
    case outOfRange(argument: String, value: Int, min: Int, max: Int)
    case invalidURL(argument: String)

    public var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Tool '\(name)' is not in the allowed tool list."
        case .argumentsNotObject:
            return "Tool input must be a JSON object."
        case .missingArgument(let name):
            return "Missing required argument '\(name)'."
        case .unexpectedArgument(let name):
            return "Unexpected argument '\(name)'."
        case let .typeMismatch(argument, expected, actual):
            return "Argument '\(argument)' must be \(expected), got \(actual)."
        case let .valueNotAllowed(argument, value, allowed):
            return "Argument '\(argument)' has value '\(value)'; allowed: \(allowed.joined(separator: ", "))."
        case .emptyString(let argument):
            return "Argument '\(argument)' must not be empty."
        case let .stringTooLong(argument, maxLength):
            return "Argument '\(argument)' is longer than \(maxLength) characters."
        case .controlCharacters(let argument):
            return "Argument '\(argument)' contains control characters."
        case let .outOfRange(argument, value, min, max):
            return "Argument '\(argument)' = \(value) is outside \(min)…\(max)."
        case .invalidURL(let argument):
            return "Argument '\(argument)' must be an absolute http(s) URL with a host."
        }
    }
}

/// Проверенные аргументы с типизированным доступом.
public struct ValidatedArguments: Sendable, Equatable {
    public let tool: ToolName
    public let values: [String: JSONValue]

    public init(tool: ToolName, values: [String: JSONValue]) {
        self.tool = tool
        self.values = values
    }

    public func string(_ name: String) -> String? {
        values[name]?.stringValue
    }

    public func int(_ name: String) -> Int? {
        values[name]?.intValue
    }

    public func bool(_ name: String) -> Bool? {
        values[name]?.boolValue
    }

    /// Обязательная строка (после валидации она гарантированно есть).
    public func requiredString(_ name: String) throws -> String {
        guard let value = string(name) else { throw ToolValidationError.missingArgument(name) }
        return value
    }

    public func requiredInt(_ name: String) throws -> Int {
        guard let value = int(name) else { throw ToolValidationError.missingArgument(name) }
        return value
    }

    public func requiredBool(_ name: String) throws -> Bool {
        guard let value = bool(name) else { throw ToolValidationError.missingArgument(name) }
        return value
    }
}

/// Строгая проверка аргументов по схеме из белого списка.
/// Не полагается на strict-режим API: модель может ошибиться, ответ может быть подменён.
public struct ToolArgumentValidator: Sendable {
    public init() {}

    public func validate(toolName rawName: String, input: JSONValue) throws -> ValidatedArguments {
        guard let definition = ToolCatalog.definition(named: rawName) else {
            throw ToolValidationError.unknownTool(rawName)
        }
        return try validate(definition: definition, input: input)
    }

    public func validate(definition: ToolDefinition, input: JSONValue) throws -> ValidatedArguments {
        // Пустой ввод для инструментов без параметров допускаем как {}.
        let object: [String: JSONValue]
        switch input {
        case .object(let value): object = value
        case .null where definition.parameters.isEmpty: object = [:]
        default: throw ToolValidationError.argumentsNotObject
        }

        // Лишние аргументы запрещены (additionalProperties: false). Сортируем для детерминизма.
        for key in object.keys.sorted() where definition.parameter(named: key) == nil {
            throw ToolValidationError.unexpectedArgument(key)
        }

        var result: [String: JSONValue] = [:]
        for parameter in definition.parameters {
            guard let raw = object[parameter.name], !raw.isNull else {
                if parameter.isRequired { throw ToolValidationError.missingArgument(parameter.name) }
                continue
            }
            result[parameter.name] = try validate(raw, against: parameter)
        }
        return ValidatedArguments(tool: definition.name, values: result)
    }

    private func validate(_ value: JSONValue, against parameter: ToolParameter) throws -> JSONValue {
        switch parameter.type {
        case let .string(maxLength, allowedValues, format):
            guard let raw = value.stringValue else {
                throw ToolValidationError.typeMismatch(argument: parameter.name, expected: "string", actual: value.typeName)
            }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw ToolValidationError.emptyString(argument: parameter.name) }
            guard text.count <= maxLength else {
                throw ToolValidationError.stringTooLong(argument: parameter.name, maxLength: maxLength)
            }
            guard !Self.containsForbiddenControlCharacters(text) else {
                throw ToolValidationError.controlCharacters(argument: parameter.name)
            }
            if let allowedValues {
                let normalized = text.lowercased()
                guard allowedValues.contains(normalized) else {
                    throw ToolValidationError.valueNotAllowed(argument: parameter.name, value: text, allowed: allowedValues)
                }
                return .string(normalized)
            }
            if format == .webURL {
                guard WebURLBuilder.validatedWebURL(text) != nil else {
                    throw ToolValidationError.invalidURL(argument: parameter.name)
                }
            }
            return .string(text)

        case let .integer(min, max):
            guard let number = value.intValue else {
                throw ToolValidationError.typeMismatch(argument: parameter.name, expected: "integer", actual: value.typeName)
            }
            guard number >= min, number <= max else {
                throw ToolValidationError.outOfRange(argument: parameter.name, value: number, min: min, max: max)
            }
            return .number(Double(number))

        case .boolean:
            guard let flag = value.boolValue else {
                throw ToolValidationError.typeMismatch(argument: parameter.name, expected: "boolean", actual: value.typeName)
            }
            return .bool(flag)
        }
    }

    /// Разрешаем только перевод строки и табуляцию; прочие управляющие символы
    /// (включая NUL, ESC, RTL-override) отклоняем.
    static func containsForbiddenControlCharacters(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if scalar == "\n" || scalar == "\t" { continue }
            if CharacterSet.controlCharacters.contains(scalar) { return true }
            // Bidi-override символы, которыми маскируют текст.
            if (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value) { return true }
        }
        return false
    }
}
