import Foundation

/// Белый список инструментов. Модель может вызвать ТОЛЬКО то, что перечислено здесь;
/// любое другое имя отклоняется до выполнения. Произвольного shell среди них нет и не будет.
public enum ToolName: String, Sendable, CaseIterable, Codable {
    // Приложения
    case openApplication = "open_application"
    case quitApplication = "quit_application"
    case switchToApplication = "switch_to_application"
    case listRunningApplications = "list_running_applications"
    // Браузер
    case openURL = "open_url"
    case openWebsite = "open_website"
    case webSearch = "web_search"
    // Система
    case getVolume = "get_volume"
    case setVolume = "set_volume"
    case changeVolume = "change_volume"
    case setMute = "set_mute"
    case getBatteryStatus = "get_battery_status"
    case getDiskSpace = "get_disk_space"
    case getSystemInfo = "get_system_info"
    case showNotification = "show_notification"
    // Окна / Accessibility
    case getActiveApplication = "get_active_application"
    case listWindows = "list_windows"
    case focusWindow = "focus_window"
    // Проекты
    case openProject = "open_project"
}

/// Тип параметра и его ограничения. Ограничения проверяются на клиенте
/// (`ToolArgumentValidator`), т.к. strict-режим API гарантирует только форму JSON.
public enum ParameterType: Sendable, Equatable {
    case string(maxLength: Int, allowedValues: [String]? = nil, format: StringFormat = .plain)
    case integer(min: Int, max: Int)
    case boolean

    public enum StringFormat: Sendable, Equatable {
        case plain
        /// http(s)-URL с хостом.
        case webURL
    }
}

public struct ToolParameter: Sendable, Equatable {
    public let name: String
    public let description: String
    public let type: ParameterType
    public let isRequired: Bool

    public init(_ name: String, _ description: String, _ type: ParameterType, required: Bool = true) {
        self.name = name
        self.description = description
        self.type = type
        self.isRequired = required
    }
}

/// Уровень риска инструмента.
public enum ToolRisk: Sendable, Equatable {
    /// Выполняется сразу.
    case safe
    /// Требует явного подтверждения пользователя перед выполнением.
    case requiresConfirmation
}

public struct ToolDefinition: Sendable, Equatable {
    public let name: ToolName
    public let description: String
    public let parameters: [ToolParameter]
    public let risk: ToolRisk

    public init(name: ToolName, description: String, parameters: [ToolParameter] = [], risk: ToolRisk = .safe) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.risk = risk
    }

    public func parameter(named name: String) -> ToolParameter? {
        parameters.first { $0.name == name }
    }

    /// Определение инструмента для Messages API в strict-режиме:
    /// `strict: true`, `additionalProperties: false`, полный список `required`.
    public func apiDefinition() -> JSONValue {
        var properties: [String: JSONValue] = [:]
        for parameter in parameters {
            properties[parameter.name] = Self.schema(for: parameter)
        }
        let required = parameters.filter(\.isRequired).map { JSONValue.string($0.name) }
        return [
            "name": .string(name.rawValue),
            "description": .string(description),
            "strict": true,
            "input_schema": [
                "type": "object",
                "properties": .object(properties),
                "required": .array(required),
                "additionalProperties": false
            ]
        ]
    }

    private static func schema(for parameter: ToolParameter) -> JSONValue {
        switch parameter.type {
        case let .string(maxLength, allowedValues, format):
            var schema: [String: JSONValue] = [
                "type": "string",
                "description": .string("\(parameter.description) (max \(maxLength) characters)")
            ]
            if let allowedValues {
                schema["enum"] = .array(allowedValues.map(JSONValue.string))
            }
            if format == .webURL {
                schema["description"] = .string("\(parameter.description) Must be an absolute http or https URL.")
            }
            return .object(schema)
        case let .integer(min, max):
            // Числовые границы описываем текстом и проверяем на клиенте.
            return [
                "type": "integer",
                "description": .string("\(parameter.description) Allowed range: \(min)…\(max).")
            ]
        case .boolean:
            return [
                "type": "boolean",
                "description": .string(parameter.description)
            ]
        }
    }
}
