import Foundation

/// Модель Claude, которую пользователь может выбрать в настройках.
public enum ClaudeModelChoice: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Claude Opus 5.5 — по умолчанию.
    case opus = "claude-opus-5-5"
    /// Claude Sonnet 5.5 — быстрее и дешевле.
    case sonnet = "claude-sonnet-5-5"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .opus: return "Claude Opus 5.5"
        case .sonnet: return "Claude Sonnet 5.5"
        }
    }
}

/// Уровень `output_config.effort`. Для голосовых команд разумен `low`/`medium`.
public enum ReasoningEffort: String, Codable, Sendable, CaseIterable, Identifiable {
    case low, medium, high
    public var id: String { rawValue }
}

/// Предпочитаемый браузер.
public enum BrowserChoice: String, Codable, Sendable, CaseIterable, Identifiable {
    case safari
    case chrome
    case systemDefault

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .systemDefault: return "Браузер по умолчанию"
        }
    }
}

/// Все пользовательские настройки NOVA AI.
public struct AppSettings: Codable, Sendable, Equatable {
    public var language: SupportedLanguage
    public var voiceEnabled: Bool
    /// `AVSpeechSynthesisVoice.identifier`; nil — системный голос для языка.
    public var voiceIdentifier: String?
    /// 0…1, отображается на диапазон AVSpeechUtterance.
    public var speechRate: Double
    /// 0…1.
    public var speechVolume: Double
    public var model: ClaudeModelChoice
    public var effort: ReasoningEffort
    public var preferredBrowser: BrowserChoice
    /// Согласие на отправку распознанного текста в Claude API.
    public var cloudProcessingConsent: Bool
    /// Показывать плавающую панель поверх окон при запуске.
    public var showFloatingPanelOnLaunch: Bool
    /// Сколько последних реплик передавать модели как контекст.
    public var contextTurnLimit: Int
    /// Каталоги, в которых ищутся проекты (open_project).
    public var projectSearchPaths: [String]

    public init(
        language: SupportedLanguage = .russian,
        voiceEnabled: Bool = true,
        voiceIdentifier: String? = nil,
        speechRate: Double = 0.5,
        speechVolume: Double = 0.9,
        model: ClaudeModelChoice = .opus,
        effort: ReasoningEffort = .low,
        preferredBrowser: BrowserChoice = .safari,
        cloudProcessingConsent: Bool = false,
        showFloatingPanelOnLaunch: Bool = false,
        contextTurnLimit: Int = 20,
        projectSearchPaths: [String] = AppSettings.defaultProjectSearchPaths
    ) {
        self.language = language
        self.voiceEnabled = voiceEnabled
        self.voiceIdentifier = voiceIdentifier
        self.speechRate = speechRate
        self.speechVolume = speechVolume
        self.model = model
        self.effort = effort
        self.preferredBrowser = preferredBrowser
        self.cloudProcessingConsent = cloudProcessingConsent
        self.showFloatingPanelOnLaunch = showFloatingPanelOnLaunch
        self.contextTurnLimit = contextTurnLimit
        self.projectSearchPaths = projectSearchPaths
    }

    public static let defaultProjectSearchPaths = [
        "~/Developer", "~/Projects", "~/IdeaProjects", "~/Documents", "~/Desktop", "~/Code", "~/src"
    ]

    /// Приводит значения к допустимым диапазонам (защита от испорченных данных).
    public func sanitized() -> AppSettings {
        var copy = self
        copy.speechRate = min(max(speechRate, 0), 1)
        copy.speechVolume = min(max(speechVolume, 0), 1)
        copy.contextTurnLimit = min(max(contextTurnLimit, 2), 100)
        return copy
    }

    // Декодирование с значениями по умолчанию, чтобы новые поля не ломали старые сохранения.
    public init(from decoder: Decoder) throws {
        let defaults = AppSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        language = try c.decodeIfPresent(SupportedLanguage.self, forKey: .language) ?? defaults.language
        voiceEnabled = try c.decodeIfPresent(Bool.self, forKey: .voiceEnabled) ?? defaults.voiceEnabled
        voiceIdentifier = try c.decodeIfPresent(String.self, forKey: .voiceIdentifier)
        speechRate = try c.decodeIfPresent(Double.self, forKey: .speechRate) ?? defaults.speechRate
        speechVolume = try c.decodeIfPresent(Double.self, forKey: .speechVolume) ?? defaults.speechVolume
        model = try c.decodeIfPresent(ClaudeModelChoice.self, forKey: .model) ?? defaults.model
        effort = try c.decodeIfPresent(ReasoningEffort.self, forKey: .effort) ?? defaults.effort
        preferredBrowser = try c.decodeIfPresent(BrowserChoice.self, forKey: .preferredBrowser) ?? defaults.preferredBrowser
        cloudProcessingConsent = try c.decodeIfPresent(Bool.self, forKey: .cloudProcessingConsent) ?? false
        showFloatingPanelOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .showFloatingPanelOnLaunch) ?? false
        contextTurnLimit = try c.decodeIfPresent(Int.self, forKey: .contextTurnLimit) ?? defaults.contextTurnLimit
        projectSearchPaths = try c.decodeIfPresent([String].self, forKey: .projectSearchPaths) ?? defaults.projectSearchPaths
    }
}

/// Хранилище настроек.
public protocol SettingsStoring: Sendable {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

/// Хранение настроек в UserDefaults в виде JSON под одним ключом.
public final class UserDefaultsSettingsStore: SettingsStoring, @unchecked Sendable {
    // UserDefaults потокобезопасен; @unchecked нужен, т.к. сам класс не помечен Sendable.
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "nova.settings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings.sanitized()
    }

    public func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings.sanitized()) else { return }
        defaults.set(data, forKey: key)
    }

    public func reset() {
        defaults.removeObject(forKey: key)
    }
}
