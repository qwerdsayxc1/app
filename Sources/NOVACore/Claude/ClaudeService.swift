import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Абстракция HTTP-транспорта (подменяется в тестах).
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Транспорт на URLSession с эфемерной конфигурацией (без кеша и cookie на диске).
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse("не HTTP-ответ")
        }
        return (data, http)
    }
}

/// Интерфейс к модели — для AIEngine и тестов.
public protocol ClaudeMessaging: Sendable {
    func send(system: String, messages: [JSONValue], tools: [ToolDefinition], configuration: ClaudeConfiguration) async throws -> ClaudeResponse
}

/// Клиент Messages API на сыром HTTP (официального Swift SDK нет).
public struct ClaudeService: ClaudeMessaging {
    private let transport: HTTPTransport
    private let apiKeyProvider: @Sendable () throws -> String?
    private let sleeper: @Sendable (TimeInterval) async throws -> Void

    public init(
        transport: HTTPTransport = URLSessionTransport(),
        apiKeyProvider: @escaping @Sendable () throws -> String?,
        sleeper: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.transport = transport
        self.apiKeyProvider = apiKeyProvider
        self.sleeper = sleeper
    }

    public func send(system: String, messages: [JSONValue], tools: [ToolDefinition], configuration: ClaudeConfiguration) async throws -> ClaudeResponse {
        guard let apiKey = try apiKeyProvider(), !apiKey.isEmpty else {
            throw ClaudeAPIError.missingAPIKey
        }
        let request = try ClaudeRequestBuilder(configuration: configuration)
            .urlRequest(apiKey: apiKey, system: system, messages: messages, tools: tools)

        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                return try await sendOnce(request)
            } catch let error as ClaudeAPIError where error.isRetryable && attempt < configuration.maxRetries {
                attempt += 1
                try await sleeper(Self.backoff(for: error, attempt: attempt))
            } catch is CancellationError {
                throw ClaudeAPIError.cancelled
            }
        }
    }

    private func sendOnce(_ request: URLRequest) async throws -> ClaudeResponse {
        let data: Data
        let response: HTTPURLResponse
        do {
            let result = try await transport.send(request)
            data = result.0
            response = result.1
        } catch let error as ClaudeAPIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ClaudeAPIError.network(error.localizedDescription)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw ClaudeResponseParser.error(
                status: response.statusCode,
                data: data,
                retryAfterHeader: response.value(forHTTPHeaderField: "retry-after")
            )
        }
        return try ClaudeResponseParser.parse(data)
    }

    static func backoff(for error: ClaudeAPIError, attempt: Int) -> TimeInterval {
        if case .rateLimited(let retryAfter?) = error {
            return min(retryAfter, 20)
        }
        return min(pow(2, Double(attempt - 1)), 8)
    }
}
