import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Извлечение идентификаторов роликов из HTML страницы результатов YouTube.
public enum YouTubeResultParser {
    private static let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

    public static func isValidVideoID(_ id: String) -> Bool {
        id.count == 11 && id.allSatisfy { allowed.contains($0) }
    }

    /// Первый идентификатор видео из результатов (`"videoId":"XXXXXXXXXXX"`).
    public static func firstVideoID(in html: String) -> String? {
        let marker = "\"videoId\":\""
        var searchRange = html.startIndex..<html.endIndex
        while let found = html.range(of: marker, range: searchRange) {
            let idStart = found.upperBound
            guard let idEnd = html.index(idStart, offsetBy: 11, limitedBy: html.endIndex) else { return nil }
            let candidate = String(html[idStart..<idEnd])
            if isValidVideoID(candidate), idEnd < html.endIndex, html[idEnd] == "\"" {
                return candidate
            }
            searchRange = found.upperBound..<html.endIndex
        }
        return nil
    }
}

public enum VideoSearchError: Error, Equatable, Sendable, LocalizedError {
    case emptyQuery
    case httpStatus(Int)
    case noResults(String)

    public var errorDescription: String? {
        switch self {
        case .emptyQuery: return "Empty video query."
        case .httpStatus(let status): return "YouTube responded with HTTP \(status)."
        case .noResults(let query): return "No YouTube video found for '\(query)'."
        }
    }
}

/// Находит первый ролик по запросу: загружает страницу результатов YouTube (без API-ключа)
/// и берёт первый videoId. Запрос идёт с Mac напрямую в YouTube, в Claude ничего не отправляется.
public struct YouTubeSearchService: VideoSearching {
    private let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func firstVideoURL(query: String) async throws -> URL {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let searchURL = WebURLBuilder.searchURL(engine: "youtube", query: trimmed) else {
            throw VideoSearchError.emptyQuery
        }
        var request = URLRequest(url: searchURL, timeoutInterval: 10)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        // Без этого cookie в ЕС вместо результатов приходит страница согласия на cookies.
        request.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw VideoSearchError.httpStatus(response.statusCode)
        }
        let html = String(decoding: data, as: UTF8.self)
        guard let id = YouTubeResultParser.firstVideoID(in: html),
              let url = WebURLBuilder.youTubeWatchURL(videoID: id) else {
            throw VideoSearchError.noResults(trimmed)
        }
        return url
    }
}
