import Foundation
import Observation
import NOVACore

/// Настройки, API-ключ и разрешения для экранов настроек и онбординга.
@MainActor
@Observable
final class SettingsViewModel {
    /// Сохраняется сразу при изменении. Голос другого языка игнорируется синтезатором,
    /// поэтому смена языка не требует сброса voiceIdentifier.
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            store.save(settings)
        }
    }

    var permissionMessage: String?

    private(set) var hasAPIKey = false
    private(set) var maskedAPIKey = ""
    var apiKeyMessage: String?

    private(set) var microphoneState: PermissionState = .notDetermined
    private(set) var speechState: PermissionState = .notDetermined
    private(set) var accessibilityState: PermissionState = .notDetermined

    private let store: SettingsStoring
    private let secrets: SecretStoring
    let permissions: PermissionsManager

    init(store: SettingsStoring, secrets: SecretStoring, permissions: PermissionsManager) {
        self.store = store
        self.secrets = secrets
        self.permissions = permissions
        self.settings = store.load()
        refreshAPIKeyState()
        refreshPermissions()
    }

    /// Показать основной интерфейс без ключа (самопроверка/скриншоты). Не сохраняется.
    var forceMainInterface = false

    var needsOnboarding: Bool {
        guard !forceMainInterface else { return false }
        return !hasAPIKey || !settings.cloudProcessingConsent
    }

    var availableVoices: [VoiceOption] {
        SpeechSynthesizer.availableVoices(for: settings.language)
    }

    // MARK: API-ключ

    func saveAPIKey(_ raw: String) {
        do {
            try secrets.saveAPIKey(raw)
            apiKeyMessage = "Ключ сохранён в Keychain."
        } catch {
            apiKeyMessage = error.localizedDescription
        }
        refreshAPIKeyState()
    }

    func deleteAPIKey() {
        do {
            try secrets.deleteAPIKey()
            apiKeyMessage = "Ключ удалён из Keychain."
        } catch {
            apiKeyMessage = error.localizedDescription
        }
        refreshAPIKeyState()
    }

    private func refreshAPIKeyState() {
        let key = (try? secrets.readAPIKey()) ?? nil
        hasAPIKey = !(key ?? "").isEmpty
        maskedAPIKey = key.map(APIKeyValidator.masked) ?? ""
    }

    // MARK: Разрешения

    func refreshPermissions() {
        microphoneState = permissions.microphone
        speechState = permissions.speechRecognition
        accessibilityState = permissions.accessibility
    }

    func requestVoicePermissions() async {
        do {
            try await permissions.ensureVoicePermissions()
            permissionMessage = nil
        } catch {
            permissionMessage = error.localizedDescription
        }
        refreshPermissions()
    }

    /// Системный запрос показывается один раз, поэтому дополнительно открываем нужную панель настроек.
    func requestAccessibility() {
        permissions.requestAccessibility()
        if permissions.accessibility != .granted {
            permissions.openSystemSettings(.accessibility)
        }
        refreshPermissions()
    }

    func openSettings(_ pane: PermissionsManager.Pane) {
        permissions.openSystemSettings(pane)
    }

    // MARK: Каталоги проектов

    func addProjectPath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !settings.projectSearchPaths.contains(trimmed) else { return }
        settings.projectSearchPaths.append(trimmed)
    }

    func removeProjectPaths(at offsets: IndexSet) {
        var paths = settings.projectSearchPaths
        for index in offsets.sorted(by: >) where paths.indices.contains(index) {
            paths.remove(at: index)
        }
        settings.projectSearchPaths = paths
    }

    func resetToDefaults() {
        let consent = settings.cloudProcessingConsent
        settings = AppSettings(cloudProcessingConsent: consent)
    }
}
