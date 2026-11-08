import AVFoundation
import NOVACore

/// Голос, доступный в настройках.
struct VoiceOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let language: String
    let isEnhanced: Bool
}

/// Делегат синтезатора: колбэки приходят не на главном потоке, поэтому он не изолирован
/// и передаёт наружу только Sendable-идентификатор фразы.
private final class SynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let onFinish: @Sendable (ObjectIdentifier) -> Void

    init(onFinish: @escaping @Sendable (ObjectIdentifier) -> Void) {
        self.onFinish = onFinish
        super.init()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish(ObjectIdentifier(utterance))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish(ObjectIdentifier(utterance))
    }
}

/// Озвучивание ответов (AVSpeechSynthesizer). Речь можно прервать в любой момент.
@MainActor
final class SpeechSynthesizer {
    private let synthesizer = AVSpeechSynthesizer()
    private var delegate: SynthesizerDelegate?
    private var continuation: CheckedContinuation<Void, Never>?
    private var currentUtterance: ObjectIdentifier?

    init() {
        let delegate = SynthesizerDelegate { [weak self] id in
            guard let self else { return }
            Task { @MainActor in self.finish(id) }
        }
        self.delegate = delegate
        synthesizer.delegate = delegate // delegate — weak-ссылка, поэтому храним объект сами
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    /// Произносит текст и возвращается, когда речь закончена или прервана.
    func speak(_ text: String, settings: AppSettings) async {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Self.voice(for: settings)
        utterance.rate = Self.utteranceRate(settings.speechRate)
        utterance.volume = Float(min(max(settings.speechVolume, 0), 1))
        utterance.preUtteranceDelay = 0.05

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuation = continuation
            self.currentUtterance = ObjectIdentifier(utterance)
            synthesizer.speak(utterance)
        }
    }

    /// Перебивание: немедленно останавливает речь.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        finish(nil)
    }

    private func finish(_ utterance: ObjectIdentifier?) {
        // Игнорируем запоздалые колбэки от предыдущей фразы.
        if let utterance, utterance != currentUtterance { return }
        currentUtterance = nil
        continuation?.resume()
        continuation = nil
    }

    // MARK: Голоса

    static func voice(for settings: AppSettings) -> AVSpeechSynthesisVoice? {
        if let identifier = settings.voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier),
           voice.language.hasPrefix(settings.language.rawValue) {
            return voice
        }
        // Лучший доступный голос для языка: premium/enhanced, иначе системный по умолчанию.
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(settings.language.rawValue) }
        if let best = candidates.max(by: { $0.quality.rawValue < $1.quality.rawValue }) {
            return best
        }
        return AVSpeechSynthesisVoice(language: settings.language.localeIdentifier)
    }

    static func availableVoices(for language: SupportedLanguage) -> [VoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language.rawValue) }
            .map { VoiceOption(id: $0.identifier, name: $0.name, language: $0.language, isEnhanced: $0.quality != .default) }
            .sorted { ($0.isEnhanced ? 0 : 1, $0.name) < ($1.isEnhanced ? 0 : 1, $1.name) }
    }

    /// Настройка 0…1 → разумный диапазон AVSpeechUtterance.rate (0.35…0.62).
    static func utteranceRate(_ setting: Double) -> Float {
        let clamped = Float(min(max(setting, 0), 1))
        return 0.35 + clamped * 0.27
    }
}
