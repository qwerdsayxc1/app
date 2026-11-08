import Foundation

/// Разбор ответа Messages API и ошибок HTTP.
public enum ClaudeResponseParser {
    public static func parse(_ data: Data) throws -> ClaudeResponse {
        let json: JSONValue
        do {
            json = try JSONValue.decode(from: data)
        } catch {
            throw ClaudeAPIError.invalidResponse("тело ответа не является JSON")
        }
        return try parse(json)
    }

    public static func parse(_ json: JSONValue) throws -> ClaudeResponse {
        guard json["type"]?.stringValue == "message" else {
            if json["type"]?.stringValue == "error" {
                throw ClaudeAPIError.badRequest(json["error"]?["message"]?.stringValue ?? "unknown error")
            }
            throw ClaudeAPIError.invalidResponse("ожидался объект type=message")
        }
        guard let content = json["content"]?.arrayValue else {
            throw ClaudeAPIError.invalidResponse("нет поля content")
        }

        var texts: [String] = []
        var toolCalls: [ToolCall] = []
        for block in content {
            switch block["type"]?.stringValue {
            case "text":
                if let text = block["text"]?.stringValue { texts.append(text) }
            case "tool_use":
                guard let id = block["id"]?.stringValue, !id.isEmpty,
                      let name = block["name"]?.stringValue, !name.isEmpty else {
                    throw ClaudeAPIError.invalidResponse("tool_use без id или name")
                }
                toolCalls.append(ToolCall(id: id, name: name, input: block["input"] ?? .object([:])))
            default:
                // thinking, redacted_thinking, fallback и прочие блоки не показываем,
                // но сохраняем в rawContent для истории.
                break
            }
        }

        let usage = json["usage"]
        return ClaudeResponse(
            id: json["id"]?.stringValue ?? "",
            model: json["model"]?.stringValue ?? "",
            stopReason: StopReason(raw: json["stop_reason"]?.stringValue, stopDetails: json["stop_details"]),
            rawContent: content,
            text: texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            toolCalls: toolCalls,
            usage: ClaudeResponse.Usage(
                inputTokens: usage?["input_tokens"]?.intValue ?? 0,
                outputTokens: usage?["output_tokens"]?.intValue ?? 0,
                cacheReadInputTokens: usage?["cache_read_input_tokens"]?.intValue ?? 0,
                cacheCreationInputTokens: usage?["cache_creation_input_tokens"]?.intValue ?? 0
            )
        )
    }

    /// Преобразует HTTP-статус и тело ошибки в типизированную ошибку.
    public static func error(status: Int, data: Data, retryAfterHeader: String?) -> ClaudeAPIError {
        let message = (try? JSONValue.decode(from: data))?["error"]?["message"]?.stringValue
            ?? String(data: data.prefix(300), encoding: .utf8)
            ?? "HTTP \(status)"
        switch status {
        case 400, 404, 413, 422: return .badRequest(message)
        case 401: return .invalidAPIKey
        case 403: return .permissionDenied(message)
        case 429: return .rateLimited(retryAfter: retryAfterHeader.flatMap(TimeInterval.init))
        case 529: return .overloaded
        default: return .server(status: status, message: message)
        }
    }
}
