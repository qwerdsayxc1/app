import Foundation
import Observation
import NOVACore

/// Проверка без Claude и без API-ключа: ручной запуск любого инструмента,
/// проверка микрофона/распознавания и озвучки.
@MainActor
@Observable
final class DiagnosticsViewModel {
    struct ToolOutcome: Equatable {
        let text: String
        let isError: Bool
        let seconds: Double
    }

    private(set) var outcomes: [ToolName: ToolOutcome] = [:]
    private(set) var runningTool: ToolName?
    private(set) var isRecording = false
    private(set) var isSpeaking = false
    private(set) var voiceTranscript = ""
    private(set) var voiceError: String?

    private let toolManager: ToolManager
    private let voice: VoiceEngine
    private let settings: SettingsViewModel

    init(toolManager: ToolManager, voice: VoiceEngine, settings: SettingsViewModel) {
        self.toolManager = toolManager
        self.voice = voice
        self.settings = settings
    }

    var tools: [ToolDefinition] { ToolCatalog.all }

    func sampleText(for tool: ToolName) -> String {
        let sample = ToolSamples.sample(for: tool)
        return sample.objectValue?.isEmpty == true ? "без аргументов" : sample.compactString()
    }

    // MARK: Инструменты

    func run(_ tool: ToolName) async {
        guard runningTool == nil else { return }
        runningTool = tool
        let started = Date()
        let record = await toolManager.execute(ToolCall(id: "diag_\(tool.rawValue)", name: tool.rawValue, input: ToolSamples.sample(for: tool)))
        outcomes[tool] = ToolOutcome(
            text: record.result.content,
            isError: record.result.isError,
            seconds: (Date().timeIntervalSince(started) * 10).rounded() / 10
        )
        runningTool = nil
    }

    var successCount: Int { outcomes.values.filter { !$0.isError }.count }
    var errorCount: Int { outcomes.values.filter(\.isError).count }

    func clearResults() {
        outcomes = [:]
    }

    // MARK: Голос

    /// Первое нажатие — запись, второе — остановка и показ распознанного текста. В сеть текст не уходит.
    func toggleRecording() async {
        voiceError = nil
        if isRecording {
            isRecording = false
            voiceTranscript = await voice.endListening()
            if voiceTranscript.isEmpty { voiceError = "Речь не распознана. Говорите ближе к микрофону." }
        } else {
            do {
                try await voice.beginListening(language: settings.settings.language, trigger: .button)
                voiceTranscript = ""
                isRecording = true
            } catch {
                voiceError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            settings.refreshPermissions()
        }
    }

    func speakSample() async {
        guard !isSpeaking else {
            voice.stopSpeaking()
            return
        }
        isSpeaking = true
        await voice.speak(Self.sampleSentence(settings.settings.language), settings: settings.settings)
        isSpeaking = false
    }

    static func sampleSentence(_ language: SupportedLanguage) -> String {
        switch language {
        case .russian: return "Привет! Я NOVA, ваш голосовой ассистент. Проверка голоса прошла успешно."
        case .ukrainian: return "Привіт! Я NOVA, ваш голосовий асистент. Перевірка голосу пройшла успішно."
        case .english: return "Hi! I'm NOVA, your voice assistant. The voice check works."
        case .german: return "Hallo! Ich bin NOVA, Ihr Sprachassistent. Die Sprachprüfung funktioniert."
        }
    }
}
