import SwiftUI
import NOVACore

/// Окно настроек: голос, AI, разрешения, память.
struct SettingsView: View {
    var body: some View {
        TabView {
            VoiceSettingsTab()
                .tabItem { Label("Голос", systemImage: "waveform") }
            AISettingsTab()
                .tabItem { Label("AI", systemImage: "sparkles") }
            PermissionsSettingsTab()
                .tabItem { Label("Разрешения", systemImage: "lock.shield") }
            MemorySettingsTab()
                .tabItem { Label("Память", systemImage: "brain") }
            DiagnosticsTab()
                .tabItem { Label("Проверка", systemImage: "checklist") }
        }
        .frame(width: 600, height: 520)
    }
}

// MARK: - Голос

private struct VoiceSettingsTab: View {
    @Environment(SettingsViewModel.self) private var model
    @Environment(AssistantViewModel.self) private var assistant

    var body: some View {
        @Bindable var model = model
        Form {
            Picker("Язык", selection: $model.settings.language) {
                ForEach(SupportedLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            Toggle("Отвечать голосом", isOn: $model.settings.voiceEnabled)
            Picker("Голос", selection: $model.settings.voiceIdentifier) {
                Text("Автоматически (лучший для языка)").tag(String?.none)
                ForEach(model.availableVoices) { voice in
                    Text(voice.isEnhanced ? "\(voice.name) ✦" : voice.name).tag(Optional(voice.id))
                }
            }
            .disabled(!model.settings.voiceEnabled)
            LabeledContent("Скорость") {
                Slider(value: $model.settings.speechRate, in: 0...1)
            }
            .disabled(!model.settings.voiceEnabled)
            LabeledContent("Громкость") {
                Slider(value: $model.settings.speechVolume, in: 0...1)
            }
            .disabled(!model.settings.voiceEnabled)
            LabeledContent("Push-to-talk") {
                Text("Удерживайте \(HotkeyManager.displayName)")
                    .foregroundStyle(.secondary)
            }
            Text("Голоса с отметкой ✦ — улучшенного качества. Дополнительные голоса: Системные настройки › Универсальный доступ › Устная речь.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

// MARK: - AI

private struct AISettingsTab: View {
    @Environment(SettingsViewModel.self) private var model
    @State private var apiKeyInput = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Claude API") {
                LabeledContent("Ключ") {
                    Text(model.hasAPIKey ? model.maskedAPIKey : "не задан")
                        .foregroundStyle(model.hasAPIKey ? .primary : .secondary)
                }
                HStack {
                    SecureField("Новый ключ sk-ant-…", text: $apiKeyInput)
                    Button("Сохранить") {
                        model.saveAPIKey(apiKeyInput)
                        apiKeyInput = ""
                    }
                    .disabled(apiKeyInput.isEmpty)
                    Button("Удалить", role: .destructive) { model.deleteAPIKey() }
                        .disabled(!model.hasAPIKey)
                }
                if let message = model.apiKeyMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Модель") {
                Picker("Модель", selection: $model.settings.model) {
                    ForEach(ClaudeModelChoice.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Глубина рассуждений", selection: $model.settings.effort) {
                    Text("Быстро (low)").tag(ReasoningEffort.low)
                    Text("Сбалансированно (medium)").tag(ReasoningEffort.medium)
                    Text("Тщательно (high)").tag(ReasoningEffort.high)
                }
                Picker("Браузер", selection: $model.settings.preferredBrowser) {
                    ForEach(BrowserChoice.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Section("Приватность") {
                Toggle("Разрешаю отправлять текст команд в Claude API", isOn: $model.settings.cloudProcessingConsent)
                Text("Отправляется только текст команды и краткая история диалога. Аудио, файлы и содержимое экрана не отправляются. Без согласия NOVA не обращается к сети.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Разрешения

private struct PermissionsSettingsTab: View {
    @Environment(SettingsViewModel.self) private var model

    var body: some View {
        Form {
            Section {
                PermissionRow(title: "Микрофон", reason: "Слышать команды, только пока вы держите кнопку/клавишу.", state: model.microphoneState) {
                    if model.microphoneState == .denied { model.openSettings(.microphone) } else { Task { await model.requestVoicePermissions() } }
                }
                PermissionRow(title: "Распознавание речи", reason: "Превращать речь в текст. По возможности — на устройстве.", state: model.speechState) {
                    if model.speechState == .denied { model.openSettings(.speechRecognition) } else { Task { await model.requestVoicePermissions() } }
                }
                PermissionRow(title: "Универсальный доступ", reason: "Список окон и переключение окон (необязательно).", state: model.accessibilityState) {
                    model.requestAccessibility()
                }
                PermissionRow(title: "Уведомления", reason: "Запрашиваются при первом уведомлении от NOVA.", state: .notDetermined) {
                    model.openSettings(.notifications)
                }
            } footer: {
                Text("NOVA не требует прав администратора. Управление громкостью работает без дополнительных разрешений.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message = model.permissionMessage {
                Text(message).foregroundStyle(.red).font(.caption)
            }
            Button("Обновить статусы") { model.refreshPermissions() }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshPermissions() }
    }
}

// MARK: - Память

private struct MemorySettingsTab: View {
    @Environment(SettingsViewModel.self) private var model
    @Environment(AssistantViewModel.self) private var assistant
    @State private var newPath = ""
    @State private var confirmClear = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Контекст разговора") {
                Stepper("Реплик в контексте: \(model.settings.contextTurnLimit)", value: $model.settings.contextTurnLimit, in: 2...100, step: 2)
                LabeledContent("Сохранено команд") { Text("\(assistant.recentCommands.count)") }
                Button("Очистить память…", role: .destructive) { confirmClear = true }
            }
            Section("Папки с проектами (для «Открой мой проект …»)") {
                List {
                    ForEach(model.settings.projectSearchPaths, id: \.self) { Text($0) }
                        .onDelete { model.removeProjectPaths(at: $0) }
                }
                .frame(minHeight: 90)
                HStack {
                    TextField("~/Projects", text: $newPath)
                    Button("Добавить") {
                        model.addProjectPath(newPath)
                        newPath = ""
                    }
                    .disabled(newPath.isEmpty)
                }
            }
            Section {
                Toggle("Показывать плавающую панель при запуске", isOn: $model.settings.showFloatingPanelOnLaunch)
                Button("Сбросить настройки") { model.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Очистить всю память NOVA?", isPresented: $confirmClear) {
            Button("Очистить", role: .destructive) { assistant.clearMemory() }
        }
    }
}
