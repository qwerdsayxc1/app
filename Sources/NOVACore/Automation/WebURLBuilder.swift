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
    public static func searchURL(engine: String, query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var components: URLComponents
        let parameterName: String
        switch engine.lowercased() {
        case "google":
            components = URLComponents(string: "https://www.google.com/search")!
            parameterName = "q"
        case "youtube":
            components = URLComponents(string: "https://www.youtube.com/results")!
            parameterName = "search_query"
        case "github":
            components = URLComponents(string: "https://github.com/search")!
            parameterName = "q"
        default:
            return nil
        }
        components.queryItems = [URLQueryItem(name: parameterName, value: trimmed)]
        return components.url
    }
}
