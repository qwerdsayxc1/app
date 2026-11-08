import Foundation
import NOVACore

/// Источник начала прослушивания. Сейчас — кнопка и горячая клавиша;
/// wake word подключается через `WakeWordDetecting` без изменения остального кода.
enum ListeningTrigger: Sendable {
    case button
    case hotkey
    case wakeWord
}

/// Точка расширения для будущего wake word («Эй, NOVA»).
/// Реализация обязана слушать микрофон только после явного включения пользователем.
@MainActor
protocol WakeWordDetecting: AnyObject {
    var onWakeWord: (() -> Void)? { get set }
    func start(language: SupportedLanguage) throws
    func stop()
}

/// Координирует распознавание и синтез: push-to-talk, перебивание, ожидание финального текста.
@MainActor
final class VoiceEngine {
    private let recognizer = SpeechRecognizer()
    private let synthesizer = SpeechSynthesizer()
    private let permissions: PermissionsManager

    private(set) var partialTranscript = ""
    private var finalTranscript: String?
    private var finalContinuation: CheckedContinuation<String, Never>?

    /// Подключается позже; по умолчанию wake word выключен.
    var wakeWordDetector: WakeWordDetecting?

    var onPartialTranscript: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?

    init(permissions: PermissionsManager) {
        self.permissions = permissions
        recognizer.onUpdate = { [weak self] update in self?.handle(update) }
        recognizer.onLevel = { [weak self] level in self?.onAudioLevel?(level) }
    }

    var isListening: Bool { recognizer.isRecording }
    var isSpeaking: Bool { synthesizer.isSpeaking }

    /// Начинает запись. Разрешения запрашиваются здесь — в момент, когда пользователь сам нажал микрофон.
    func beginListening(language: SupportedLanguage, trigger: ListeningTrigger) async throws {
        synthesizer.stop() // перебивание ассистента
        try await permissions.ensureVoicePermissions()
        partialTranscript = ""
        finalTranscript = nil
        try recognizer.start(language: language, contextualStrings: Self.contextualStrings)
    }

    /// Завершает запись и ждёт финальный текст (не дольше `timeout`).
    func endListening(timeout: TimeInterval = 2.0) async -> String {
        guard recognizer.isRecording else {
            return (finalTranscript ?? partialTranscript).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        recognizer.finishAudio()
        let text = await waitForFinal(timeout: timeout)
        recognizer.stop()
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Отмена без отправки команды.
    func cancelListening() {
        recognizer.stop()
        resolveFinal(partialTranscript)
        partialTranscript = ""
    }

    func speak(_ text: String, settings: AppSettings) async {
        await synthesizer.speak(text, settings: settings)
    }

    func stopSpeaking() {
        synthesizer.stop()
    }

    // MARK: - Private

    private func handle(_ update: RecognitionUpdate) {
        if !update.text.isEmpty {
            partialTranscript = update.text
            onPartialTranscript?(update.text)
        }
        if update.isFinal {
            finalTranscript = update.text
            resolveFinal(update.text)
        } else if update.errorCode != nil {
            // 1110 «нет речи», 216/203 — отмена/недоступность: отдаём то, что успели распознать.
            finalTranscript = partialTranscript
            resolveFinal(partialTranscript)
        }
    }

    private func waitForFinal(timeout: TimeInterval) async -> String {
        if let finalTranscript { return finalTranscript }
        return await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            finalContinuation = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard let self else { return }
                self.resolveFinal(self.partialTranscript)
            }
        }
    }

    private func resolveFinal(_ text: String) {
        finalContinuation?.resume(returning: text)
        finalContinuation = nil
    }

    /// Подсказки распознавателю: команды и названия приложений.
    static let contextualStrings: [String] = [
        "NOVA", "YouTube", "GitHub", "Telegram", "Safari", "Chrome", "IntelliJ IDEA", "Xcode", "Claude API", "Python",
        "открой", "запусти", "закрой", "найди", "громкость", "выключи звук", "батарея",
        "відкрий", "знайди", "гучність", "öffne", "suche", "Lautstärke"
    ]
}
