import SwiftUI
import NOVACore

/// Первый запуск: API-ключ, согласие на облачную обработку, разрешения с объяснением.
struct OnboardingView: View {
    @Environment(SettingsViewModel.self) private var settings
    @State private var apiKeyInput = ""

    var body: some View {
        @Bindable var settings = settings
        ScrollView {
            VStack(spacing: 24) {
                OrbView(status: .idle, level: 0, size: 150)
                Text("Добро пожаловать в NOVA AI")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accentGradient)
                Text("Три коротких шага — и можно управлять Mac голосом.")
                    .foregroundStyle(Theme.textSecondary)

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        StepHeader(number: 1, title: "API-ключ Anthropic", done: settings.hasAPIKey)
                        Text("Ключ хранится только в связке ключей macOS (Keychain). Получить его можно на platform.claude.com.")
                            .font(.callout)
                            .foregroundStyle(Theme.textSecondary)
                        HStack {
                            SecureField(settings.hasAPIKey ? settings.maskedAPIKey : "sk-ant-…", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                            Button("Сохранить") {
                                settings.saveAPIKey(apiKeyInput)
                                apiKeyInput = ""
                            }
                            .disabled(apiKeyInput.isEmpty)
                        }
                        if let message = settings.apiKeyMessage {
                            Text(message).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        StepHeader(number: 2, title: "Согласие на обработку команд", done: settings.settings.cloudProcessingConsent)
                        Text("Голос распознаётся на Mac (по возможности — полностью офлайн). В Claude API отправляется только текст команды и краткая история диалога. Аудио, файлы и содержимое экрана не отправляются.")
                            .font(.callout)
                            .foregroundStyle(Theme.textSecondary)
                        Toggle("Разрешаю отправлять текст команд в Claude API", isOn: $settings.settings.cloudProcessingConsent)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        StepHeader(number: 3, title: "Разрешения macOS", done: settings.microphoneState == .granted && settings.speechState == .granted)
                        PermissionRow(
                            title: "Микрофон и распознавание речи",
                            reason: "Чтобы слышать команды. Микрофон включается только когда вы нажимаете кнопку или горячую клавишу.",
                            state: settings.microphoneState == .granted && settings.speechState == .granted ? .granted : settings.microphoneState
                        ) {
                            if settings.microphoneState == .denied {
                                settings.openSettings(.microphone)
                            } else if settings.speechState == .denied {
                                settings.openSettings(.speechRecognition)
                            } else {
                                Task { await settings.requestVoicePermissions() }
                            }
                        }
                        PermissionRow(
                            title: "Универсальный доступ (необязательно)",
                            reason: "Нужен только для работы с окнами: список окон, переключение окна.",
                            state: settings.accessibilityState
                        ) {
                            settings.requestAccessibility()
                        }
                        if let message = settings.permissionMessage {
                            Text(message).font(.caption).foregroundStyle(Theme.danger)
                        }
                    }
                }

                VStack(spacing: 6) {
                    Button("Продолжить без ключа") {
                        settings.forceMainInterface = true
                    }
                    .buttonStyle(.borderless)
                    Text("Интерфейс, микрофон, голос и все действия можно проверить без ключа: Настройки (⌘,) → вкладка «Проверка». Голосовые команды заработают после ввода ключа.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 560)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .onAppear { settings.refreshPermissions() }
    }
}

private struct StepHeader: View {
    let number: Int
    let title: String
    let done: Bool

    var body: some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .foregroundStyle(done ? Theme.mint : Theme.violet)
                .font(.title2)
            Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
        }
    }
}

struct PermissionRow: View {
    let title: String
    let reason: String
    let state: PermissionState
    let request: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(Theme.textPrimary)
                Text(reason).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if state == .granted {
                Label("Разрешено", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.mint)
                    .font(.caption)
            } else {
                Button(state == .denied ? "Открыть настройки" : "Разрешить", action: request)
            }
        }
    }
}
