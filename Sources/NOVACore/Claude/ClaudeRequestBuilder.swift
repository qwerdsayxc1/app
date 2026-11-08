import Foundation

/// Собирает тело и заголовки запроса `POST /v1/messages`.
///
/// Ключевые решения (сверено со скилом claude-api):
/// - `anthropic-version: 2026-10-21`; `temperature/top_p/top_k` не отправляем (400 на этой версии).
/// - `thinking` не передаём: на Opus 5.5 / Sonnet 5.5 адаптивное мышление включено по умолчанию,
///   а `disabled` даёт 400. Глубину регулируем `output_config.effort`.
/// - `tool_choice: auto` — принудительный `any`/`tool` на этих моделях запрещён (400).
/// - Инструменты в strict-режиме; порядок инструментов и системный промпт стабильны → кеш промпта.
/// - Серверный fallback при отказе: `fallbacks: "default"` + beta-заголовок.
public struct ClaudeRequestBuilder: Sendable {
    public let configuration: ClaudeConfiguration

    public init(configuration: ClaudeConfiguration) {
        self.configuration = configuration
    }

    public func body(system: String, messages: [JSONValue], tools: [ToolDefinition]) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(configuration.model.rawValue),
            "max_tokens": .number(Double(configuration.maxTokens)),
            "system": [
                [
                    "type": "text",
                    "text": .string(system),
                    "cache_control": ["type": "ephemeral"]
                ]
            ],
            "messages": .array(messages),
            "output_config": ["effort": .string(configuration.effort.rawValue)]
        ]
        if !tools.isEmpty {
            body["tools"] = ToolCatalog.apiTools(tools)
            body["tool_choice"] = ["type": "auto"]
        }
        if configuration.useServerSideFallback {
            body["fallbacks"] = "default"
        }
        return .object(body)
    }

    public func headers(apiKey: String) -> [String: String] {
        var headers = [
            "x-api-key": apiKey,
            "anthropic-version": configuration.apiVersion,
            "content-type": "application/json",
            "accept": "application/json"
        ]
        if configuration.useServerSideFallback {
            headers["anthropic-beta"] = ClaudeConfiguration.serverSideFallbackBeta
        }
        return headers
    }

    public func urlRequest(apiKey: String, system: String, messages: [JSONValue], tools: [ToolDefinition]) throws -> URLRequest {
        var request = URLRequest(url: configuration.endpoint, timeoutInterval: configuration.requestTimeout)
        request.httpMethod = "POST"
        for (field, value) in headers(apiKey: apiKey) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try body(system: system, messages: messages, tools: tools).encodedData()
        return request
    }
}
