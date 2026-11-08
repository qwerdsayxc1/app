import Foundation
import NOVACore

/// Корень композиции: создаёт все сервисы и связывает их через протоколы (DI).
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let settings: SettingsViewModel
    let assistant: AssistantViewModel
    let permissions: PermissionsManager
    /// Предупреждение, если постоянная память недоступна (работаем с памятью в RAM).
    let memoryWarning: String?

    private let toolManager: ToolManager

    private init() {
        let keychain = KeychainSecretStore()
        let permissions = PermissionsManager()
        let settings = SettingsViewModel(store: UserDefaultsSettingsStore(), secrets: keychain, permissions: permissions)
        let currentSettings: () -> AppSettings = { [unowned settings] in settings.settings }

        // MacAutomation
        let applications = ApplicationManager()
        let notifications = NotificationService()
        let services = ToolServices(
            applications: applications,
            browser: BrowserController(),
            system: SystemManager(),
            notifications: notifications,
            windows: AccessibilityService(applications: applications),
            projects: ProjectOpener(),
            media: MediaController(),
            videos: YouTubeSearchService(),
            productivity: ProductivityService(notifications: notifications),
            settings: currentSettings
        )
        let toolManager = ToolManager(
            handlers: ToolHandlerRegistry.makeHandlers(services),
            language: { [unowned settings] in settings.settings.language }
        )

        // AI Brain — ключ читается из Keychain при каждом запросе и нигде не кешируется на диске.
        let claude = ClaudeService(apiKeyProvider: { try keychain.readAPIKey() })
        let engine = AIEngine(claude: claude, toolManager: toolManager, settings: currentSettings)

        // Память
        let memoryStore: MemoryStore
        var memoryWarning: String?
        do {
            memoryStore = SwiftDataMemoryStore(container: try SwiftDataMemoryStore.makeContainer())
        } catch {
            memoryStore = InMemoryMemoryStore()
            memoryWarning = "Не удалось открыть хранилище памяти (\(error.localizedDescription)). История будет храниться только до выхода."
        }
        let memory = MemoryManager(store: memoryStore)

        let voice = VoiceEngine(permissions: permissions)
        let assistant = AssistantViewModel(engine: engine, memory: memory, voice: voice, settings: settings)
        toolManager.confirmationProvider = assistant

        self.settings = settings
        self.assistant = assistant
        self.permissions = permissions
        self.memoryWarning = memoryWarning
        self.toolManager = toolManager
    }
}
