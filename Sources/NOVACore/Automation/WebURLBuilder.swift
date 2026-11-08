import Foundation

/// Построение и проверка URL для браузерных инструментов.
public enum WebURLBuilder {
    /// Принимает только абсолютные http/https-URL с непустым хостом.
    /// Это не даёт модели открыть `file://`, `javascript:` или произвольные URL-схемы приложений.
    public static func validatedWebURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url else {
            return nil
        }
        return url
    }

    public static func websiteURL(for site: String) -> URL? {
        let address: String
        switch site.lowercased() {
        case "youtube": address = "https://www.youtube.com"
        case "github": address = "https://github.com"
        case "google": address = "https://www.google.com"
        case "apple": address = "https://www.apple.com"
        case "wikipedia": address = "https://www.wikipedia.org"
        case "stackoverflow": address = "https://stackoverflow.com"
        case "gmail": address = "https://mail.google.com"
        case "maps": address = "https://maps.google.com"
        default: return nil
        }
        return URL(string: address)
    }

    /// URL страницы результатов поиска. Запрос кодируется через URLComponents.
    /// `language` нужен Википедии (раздел языка) и переводчику (язык перевода).
    public static func searchURL(engine: String, query: String, language: SupportedLanguage = .english) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let base: String
        var items: [URLQueryItem]
        switch engine.lowercased() {
        case "google":
            base = "https://www.google.com/search"
            items = [URLQueryItem(name: "q", value: trimmed)]
        case "youtube":
            base = "https://www.youtube.com/results"
            items = [URLQueryItem(name: "search_query", value: trimmed)]
        case "github":
            base = "https://github.com/search"
            items = [URLQueryItem(name: "q", value: trimmed)]
        case "wikipedia":
            base = "https://\(language.rawValue).wikipedia.org/w/index.php"
            items = [URLQueryItem(name: "search", value: trimmed)]
        case "maps":
            base = "https://www.google.com/maps/search/"
            items = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: trimmed)]
        case "images":
            base = "https://www.google.com/search"
            items = [URLQueryItem(name: "tbm", value: "isch"), URLQueryItem(name: "q", value: trimmed)]
        case "translate":
            base = "https://translate.google.com/"
            items = [
                URLQueryItem(name: "sl", value: "auto"),
                URLQueryItem(name: "tl", value: language.rawValue),
                URLQueryItem(name: "text", value: trimmed),
                URLQueryItem(name: "op", value: "translate")
            ]
        default:
            return nil
        }
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = items
        return components.url
    }

    public static func youTubeWatchURL(videoID: String) -> URL? {
        guard YouTubeResultParser.isValidVideoID(videoID) else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(videoID)")
    }
}
