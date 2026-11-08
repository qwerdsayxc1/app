import AVFoundation
import Speech
import NOVACore

/// Обновление распознавания — только Sendable-значения (без SFSpeechRecognitionResult).
struct RecognitionUpdate: Sendable {
    let text: String
    let isFinal: Bool
    let errorCode: Int?
    let errorMessage: String?
}

enum VoiceError: Error, LocalizedError, Equatable {
    case microphoneDenied
    case speechRecognitionDenied
    case languageNotSupported(String)
    case recognizerUnavailable
    case noInputDevice
    case audioEngine(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Нет доступа к микрофону. Разрешите его в Системных настройках › Конфиденциальность и безопасность › Микрофон."
        case .speechRecognitionDenied:
            return "Нет доступа к распознаванию речи. Разрешите его в Системных настройках › Конфиденциальность и безопасность › Распознавание речи."
        case .languageNotSupported(let locale):
            return "Распознавание речи для \(locale) недоступно на этом Mac."
        case .recognizerUnavailable:
            return "Распознавание речи сейчас недоступно (проверьте интернет или скачайте язык для диктовки)."
        case .noInputDevice:
            return "Не найден микрофон."
        case .audioEngine(let message):
            return "Ошибка аудио: \(message)"
        }
    }
}

/// Распознавание речи с микрофона (SFSpeechRecognizer + AVAudioEngine).
/// Микрофон открыт только между start() и finishAudio()/stop() — постоянного прослушивания нет.
@MainActor
final class SpeechRecognizer {
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private(set) var isRecording = false
    private var generation = 0

    var onUpdate: ((RecognitionUpdate) -> Void)?
    var onLevel: ((Float) -> Void)?

    func start(language: SupportedLanguage, contextualStrings: [String]) throws {
        stop()
        generation += 1
        let locale = Locale(identifier: language.localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw VoiceError.languageNotSupported(language.localeIdentifier)
        }
        guard recognizer.isAvailable else { throw VoiceError.recognizerUnavailable }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.contextualStrings = contextualStrings
        // Приватность: если язык поддерживает распознавание на устройстве — звук не покидает Mac.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceError.noInputDevice }

        let box = RequestBox(request: request)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTapBlock(box: box, levelSink: makeLevelSink()))
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw VoiceError.audioEngine(error.localizedDescription)
        }

        self.recognizer = recognizer
        self.request = request
        self.task = recognizer.recognitionTask(with: request, resultHandler: Self.makeResultHandler(sink: makeUpdateSink()))
        isRecording = true
    }

    /// Push-to-talk отпущен: прекращаем запись, но ждём финальный результат.
    func finishAudio() {
        guard isRecording else { return }
        stopEngine()
        request?.endAudio()
        isRecording = false
    }

    /// Полная остановка с отменой задачи распознавания.
    func stop() {
        generation += 1
        if isRecording { stopEngine() }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
        isRecording = false
        onLevel?(0)
    }

    private func stopEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    // MARK: - Callbacks (вызываются на аудио-потоке и очереди Speech)

    /// Колбэки старых сессий (например, ошибка «cancelled» после stop()) игнорируются.
    private func makeUpdateSink() -> @Sendable (RecognitionUpdate) -> Void {
        let session = generation
        return { [weak self] update in
            guard let self else { return }
            Task { @MainActor in
                guard self.generation == session else { return }
                self.onUpdate?(update)
            }
        }
    }

    private func makeLevelSink() -> @Sendable (Float) -> Void {
        let session = generation
        return { [weak self] level in
            guard let self else { return }
            Task { @MainActor in
                guard self.generation == session, self.isRecording else { return }
                self.onLevel?(level)
            }
        }
    }

    /// nonisolated: блок вызывается на аудио-потоке и не должен быть изолирован на MainActor.
    private nonisolated static func makeTapBlock(
        box: RequestBox,
        levelSink: @escaping @Sendable (Float) -> Void
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in
            box.request.append(buffer)
            levelSink(AudioLevel.normalizedLevel(of: buffer))
        }
    }

    private nonisolated static func makeResultHandler(
        sink: @escaping @Sendable (RecognitionUpdate) -> Void
    ) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let nsError = error as NSError?
            sink(RecognitionUpdate(
                text: result?.bestTranscription.formattedString ?? "",
                isFinal: result?.isFinal ?? false,
                errorCode: nsError?.code,
                errorMessage: nsError?.localizedDescription
            ))
        }
    }
}

/// `SFSpeechAudioBufferRecognitionRequest.append` рассчитан на вызов с аудио-потока.
private final class RequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    init(request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
}

/// Уровень сигнала 0…1 для анимации звуковой волны.
enum AudioLevel {
    static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<frames {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = (sum / Float(frames)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        // -50 dB → 0, 0 dB → 1
        return min(1, max(0, (decibels + 50) / 50))
    }
}
