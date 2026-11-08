import Foundation

/// Сопоставляет произнесённое название приложения (на ru/uk/en/de, с опечатками
/// распознавания) с bundle identifier и каноническим именем.
public struct AppAliasResolver: Sendable {
    public struct KnownApp: Sendable, Equatable {
        public let canonicalName: String
        /// Возможные bundle ID в порядке предпочтения (разные редакции/версии).
        public let bundleIdentifiers: [String]
        public let aliases: [String]
    }

    public static let defaultApps: [KnownApp] = [
        KnownApp(canonicalName: "Safari", bundleIdentifiers: ["com.apple.Safari"], aliases: ["safari", "сафари", "сафарі", "браузер safari"]),
        KnownApp(canonicalName: "Google Chrome", bundleIdentifiers: ["com.google.Chrome"], aliases: ["chrome", "google chrome", "хром", "гугл хром", "хроме"]),
        KnownApp(canonicalName: "Telegram", bundleIdentifiers: ["ru.keepcoder.Telegram", "org.telegram.desktop"], aliases: ["telegram", "телеграм", "телеграмм", "телега", "телеграма"]),
        KnownApp(canonicalName: "IntelliJ IDEA", bundleIdentifiers: ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"], aliases: ["intellij", "intellij idea", "idea", "интеллидж", "интелидж", "интеллij", "интеллиджей", "идея", "intellij idea ultimate", "intellij idea community"]),
        KnownApp(canonicalName: "Xcode", bundleIdentifiers: ["com.apple.dt.Xcode"], aliases: ["xcode", "икскод", "иксекод", "экскод", "x code"]),
        KnownApp(canonicalName: "Visual Studio Code", bundleIdentifiers: ["com.microsoft.VSCode"], aliases: ["vscode", "vs code", "visual studio code", "вс код", "вскод", "visual studio"]),
        KnownApp(canonicalName: "Finder", bundleIdentifiers: ["com.apple.finder"], aliases: ["finder", "файндер", "файнде", "проводник"]),
        KnownApp(canonicalName: "Terminal", bundleIdentifiers: ["com.apple.Terminal"], aliases: ["terminal", "терминал", "термінал"]),
        KnownApp(canonicalName: "Music", bundleIdentifiers: ["com.apple.Music"], aliases: ["music", "apple music", "музыка", "музика", "musik"]),
        KnownApp(canonicalName: "Mail", bundleIdentifiers: ["com.apple.mail"], aliases: ["mail", "почта", "пошта", "apple mail"]),
        KnownApp(canonicalName: "Notes", bundleIdentifiers: ["com.apple.Notes"], aliases: ["notes", "заметки", "нотатки", "notizen"]),
        KnownApp(canonicalName: "Calendar", bundleIdentifiers: ["com.apple.iCal"], aliases: ["calendar", "календарь", "календар", "kalender"]),
        KnownApp(canonicalName: "Messages", bundleIdentifiers: ["com.apple.MobileSMS"], aliases: ["messages", "сообщения", "повідомлення", "nachrichten", "imessage"]),
        KnownApp(canonicalName: "System Settings", bundleIdentifiers: ["com.apple.systempreferences"], aliases: ["system settings", "settings", "системные настройки", "настройки", "налаштування", "systemeinstellungen"]),
        KnownApp(canonicalName: "Slack", bundleIdentifiers: ["com.tinyspeck.slackmacgap"], aliases: ["slack", "слак", "слэк"]),
        KnownApp(canonicalName: "Spotify", bundleIdentifiers: ["com.spotify.client"], aliases: ["spotify", "спотифай", "спотіфай"]),
        KnownApp(canonicalName: "WhatsApp", bundleIdentifiers: ["net.whatsapp.WhatsApp", "desktop.WhatsApp"], aliases: ["whatsapp", "ватсап", "вотсап", "ватсапп"]),
        KnownApp(canonicalName: "Discord", bundleIdentifiers: ["com.hnc.Discord"], aliases: ["discord", "дискорд"]),
        KnownApp(canonicalName: "Zoom", bundleIdentifiers: ["us.zoom.xos"], aliases: ["zoom", "зум"]),
        KnownApp(canonicalName: "Preview", bundleIdentifiers: ["com.apple.Preview"], aliases: ["preview", "просмотр", "перегляд", "vorschau"]),
        KnownApp(canonicalName: "Photos", bundleIdentifiers: ["com.apple.Photos"], aliases: ["photos", "фото", "фотографии", "fotos"]),
        KnownApp(canonicalName: "App Store", bundleIdentifiers: ["com.apple.AppStore"], aliases: ["app store", "апп стор", "эп стор", "аппстор"]),
        KnownApp(canonicalName: "Activity Monitor", bundleIdentifiers: ["com.apple.ActivityMonitor"], aliases: ["activity monitor", "мониторинг системы", "монитор активности"]),
        KnownApp(canonicalName: "Calculator", bundleIdentifiers: ["com.apple.calculator"], aliases: ["calculator", "калькулятор", "rechner"]),
        KnownApp(canonicalName: "Firefox", bundleIdentifiers: ["org.mozilla.firefox"], aliases: ["firefox", "файрфокс", "фаерфокс"]),
        KnownApp(canonicalName: "Arc", bundleIdentifiers: ["company.thebrowser.Browser"], aliases: ["arc", "арк"]),
        KnownApp(canonicalName: "PyCharm", bundleIdentifiers: ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"], aliases: ["pycharm", "пайчарм"]),
        KnownApp(canonicalName: "Android Studio", bundleIdentifiers: ["com.google.android.studio"], aliases: ["android studio", "андроид студио", "андроид студия"])
    ]

    private let apps: [KnownApp]

    public init(apps: [KnownApp] = AppAliasResolver.defaultApps) {
        self.apps = apps
    }

    /// Нормализация: нижний регистр, без диакритики, без пунктуации, одиночные пробелы.
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")
        let cleaned = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(cleaned)
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// Ищет известное приложение по названию. Сначала точное совпадение алиаса,
    /// затем совпадение без пробелов (например «vs code» ↔ «vscode»).
    public func resolve(_ spokenName: String) -> KnownApp? {
        let normalized = Self.normalize(spokenName)
        guard !normalized.isEmpty else { return nil }
        let compact = normalized.replacingOccurrences(of: " ", with: "")

        for app in apps {
            let candidates = ([app.canonicalName] + app.aliases).map(Self.normalize)
            if candidates.contains(normalized) { return app }
        }
        for app in apps {
            let candidates = ([app.canonicalName] + app.aliases)
                .map { Self.normalize($0).replacingOccurrences(of: " ", with: "") }
            if candidates.contains(compact) { return app }
        }
        return nil
    }

    /// Насколько имя установленного приложения похоже на запрос (0 — не похоже).
    /// Используется для поиска по /Applications, когда алиаса нет в таблице.
    public static func matchScore(query: String, candidate: String) -> Int {
        let q = normalize(query).replacingOccurrences(of: " ", with: "")
        let c = normalize(candidate).replacingOccurrences(of: " ", with: "")
        guard !q.isEmpty, !c.isEmpty else { return 0 }
        if q == c { return 100 }
        if c.hasPrefix(q) { return 80 }
        if q.hasPrefix(c), c.count >= 3 { return 70 }
        if c.contains(q), q.count >= 3 { return 60 }
        return 0
    }
}
