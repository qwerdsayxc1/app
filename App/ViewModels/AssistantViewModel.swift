import Foundation
import Observation
import NOVACore

/// Главная ViewModel: голосовой цикл «слушаю → думаю → выполняю → говорю»,
/// перебивание, подтверждение опасных действий, история.
@MainActor
@Observable
final class AssistantViewModel: ConfirmationProviding {
    // MARK: Состояние для UI
    private(set) var status: AssistantStatus = .idle
    private(set) var transcript = ""
    private(set) var reply = ""
    private(set) var errorMessage: String?
    private(set) var audioLevel: Float = 0
    private(set) var lastActions: [String] = []
    private(set) var history: [ChatMessage] = []
    private(set) var recentCommands: [CommandRecord] = []
    private(set) var pendingConfirmation: ConfirmationRequest?
    var typedCommand = ""

    // MARK: Зависимости
    private let engine: AIEngine
    private let memory: MemoryManager
    private let voice: VoiceEngine
    let settingsModel: SettingsViewModel
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var confirmationContinuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var listeningStartTask: Task<Void, Never>?
    @ObservationIgnored private var isStartingListening = false
    @ObservationIgnored private var earlyConfirmationAnswer: Bool?

    init(engine: AIEngine, memory: MemoryManager, voice: VoiceEngine, settings: SettingsViewModel) {
        self.engine = engine
        self.memory = memory
        self.voice = voice
        self.settingsModel = settings
        voice.onPartialTranscript = { [weak self] text in self?.transcript = text }
        voice.onAudioLevel = { [weak self] level in self?.audioLevel = level }
        refreshMemory()
    }

    private var settings: AppSettings { settingsModel.settings }

    var isBusy: Bool { status == .thinking || status == .executing }

    // MARK: - Микрофон / push-to-talk

    /// Кнопка микрофона: начать / закончить запись; если ассистент говорит или думает — перебить.
    func micButtonTapped() {
        switch status {
        case .listening:
            finishListening()
        case .idle:
            startListening(trigger: .button)
        case .speaking, .thinking, .executing:
            if pendingConfirmation == nil { interrupt() }
            startListening(trigger: .button)
        }
    }

    func hotkeyPressed() {
        guard status != .listening else { return }
        if pendingConfirmation == nil, status != .idle { interrupt() }
        startListening(trigger: .hotkey)
    }

    func hotkeyReleased() {
        // Клавишу могли отпустить, пока ещё идёт запуск записи (например, запрос разрешений).
        if status == .listening || isStartingListening { finishListening() }
    }

    private func startListening(trigger: ListeningTrigger) {
        guard !isStartingListening else { return }
        voice.stopSpeaking()
        errorMessage = nil
        isStartingListening = true
        listeningStartTask = Task {
            do {
                try await voice.beginListening(language: settings.language, trigger: trigger)
                transcript = ""
                status = .listening
            } catch {
                show(error)
            }
            isStartingListening = false
            settingsModel.refreshPermissions()
        }
    }

    private func finishListening() {
        Task {
            await listeningStartTask?.value
            guard status == .listening else { return } // запуск записи не удался
            let text = await voice.endListening()
            audioLevel = 0
            if pendingConfirmation != nil {
                status = .executing
                handleConfirmationAnswer(text)
            } else {
                status = .idle
                submit(text)
            }
        }
    }

    // MARK: - Команды

    func submitTypedCommand() {
        let text = typedCommand
        typedCommand = ""
        submit(text)
    }

    func submit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = .idle
            return
        }
        processingTask?.cancel()
        processingTask = Task { await process(trimmed) }
    }

    private func process(_ text: String) async {
        transcript = text
        reply = ""
        errorMessage = nil
        lastActions = []
        status = .thinking

        do {
            let context = memory.conversationContext(turnLimit: settings.contextTurnLimit)
            let result = try await engine.process(text, history: context) { [weak self] event in
                self?.handle(event)
            }
            let answer = result.reply.isEmpty ? Self.doneText(settings.language) : result.reply
            reply = answer
            lastActions = result.actionSummaries
            memory.recordExchange(utterance: text, reply: answer, actions: result.actionSummaries, succeeded: result.succeeded)
            refreshMemory()
            await speak(answer)
        } catch is CancellationError {
            status = .idle
        } catch ClaudeAPIError.cancelled {
            status = .idle
        } catch {
            show(error)
            memory.recordExchange(utterance: text, reply: errorMessage ?? "", actions: [], succeeded: false)
            refreshMemory()
            if let message = errorMessage { await speak(message) }
        }
        if status != .listening { status = .idle }
    }

    private func handle(_ event: AIEngineEvent) {
        switch event {
        case .thinking: status = .thinking
        case .executing: status = .executing
        case .toolFinished: break
        }
    }

    private func speak(_ text: String) async {
        guard settings.voiceEnabled, !Task.isCancelled else { return }
        status = .speaking
        await voice.speak(text, settings: settings)
        if status == .speaking { status = .idle }
    }

    /// Перебить ассистента: остановить речь, отменить запрос и выполнение.
    func interrupt() {
        voice.stopSpeaking()
        processingTask?.cancel()
        processingTask = nil
        resolveConfirmation(false)
        if status == .listening { voice.cancelListening() }
        audioLevel = 0
        status = .idle
    }

    // MARK: - Подтверждение опасных действий

    func requestConfirmation(_ request: ConfirmationRequest) async -> Bool {
        resolveConfirmation(false) // предыдущий запрос (если был) считается отклонённым
        earlyConfirmationAnswer = nil
        pendingConfirmation = request
        if settings.voiceEnabled {
            status = .speaking
            await voice.speak(request.prompt, settings: settings)
            if status == .speaking { status = .executing }
        }
        // Пользователь мог ответить кнопкой, пока звучал вопрос.
        if let answer = earlyConfirmationAnswer {
            earlyConfirmationAnswer = nil
            return answer
        }
        guard pendingConfirmation?.id == request.id, !Task.isCancelled else { return false }
        return await withCheckedContinuation { continuation in
            confirmationContinuation = continuation
        }
    }

    func resolveConfirmation(_ approved: Bool) {
        guard pendingConfirmation != nil || confirmationContinuation != nil else { return }
        pendingConfirmation = nil
        if let continuation = confirmationContinuation {
            confirmationContinuation = nil
            continuation.resume(returning: approved)
        } else {
            earlyConfirmationAnswer = approved
        }
    }

    private func handleConfirmationAnswer(_ text: String) {
        transcript = text
        switch ConfirmationParser.parse(text) {
        case .some(let approved):
            resolveConfirmation(approved)
        case .none:
            errorMessage = Self.unclearConfirmationText(settings.language)
        }
    }

    // MARK: - Память

    func clearMemory() {
        memory.clearAll()
        engine.resetConversation()
        transcript = ""
        reply = ""
        lastActions = []
        refreshMemory()
    }

    private func refreshMemory() {
        history = memory.history(limit: 100)
        recentCommands = memory.recentCommands(limit: 30)
    }

    // MARK: - Ошибки и тексты

    private func show(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        reply = errorMessage ?? ""
        status = .idle
    }

    static func doneText(_ language: SupportedLanguage) -> String {
        switch language {
        case .russian: return "Готово."
        case .ukrainian: return "Готово."
        case .english: return "Done."
        case .german: return "Erledigt."
        }
    }

    static func unclearConfirmationText(_ language: SupportedLanguage) -> String {
        switch language {
        case .russian: return "Не понял ответ. Скажите «да» или «нет», или нажмите кнопку."
        case .ukrainian: return "Не зрозумів відповідь. Скажіть «так» або «ні», або натисніть кнопку."
        case .english: return "I didn't catch that. Say “yes” or “no”, or use the buttons."
        case .german: return "Nicht verstanden. Sagen Sie „ja“ oder „nein“ oder nutzen Sie die Tasten."
        }
    }
}
