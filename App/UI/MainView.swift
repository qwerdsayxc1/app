import SwiftUI
import NOVACore

/// Главный экран: Orb, статус, волна, распознанная фраза, ответ, микрофон, история, настройки.
struct MainView: View {
    @Environment(AssistantViewModel.self) private var assistant
    @Environment(SettingsViewModel.self) private var settings

    var body: some View {
        ZStack {
            NovaBackground()
            if settings.needsOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    AssistantPanel()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    HistorySidebar()
                        .frame(width: 320)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: settings.needsOnboarding)
    }
}

/// Левая часть: Orb и диалог.
private struct AssistantPanel: View {
    @Environment(AssistantViewModel.self) private var assistant

    var body: some View {
        @Bindable var assistant = assistant
        VStack(spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NOVA AI")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accentGradient)
                    Text("Голосовой ассистент для Mac")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                StatusBadge(status: assistant.status)
                SettingsLink {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.borderless)
                .help("Настройки")
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            if let request = assistant.pendingConfirmation {
                ConfirmationBanner(request: request) { approved in
                    assistant.resolveConfirmation(approved)
                }
                .frame(maxWidth: 520)
            }

            Spacer(minLength: 0)

            OrbView(status: assistant.status, level: assistant.audioLevel, size: 260)
                .onTapGesture { assistant.micButtonTapped() }

            WaveformView(status: assistant.status, level: assistant.audioLevel)
                .frame(height: 64)
                .padding(.horizontal, 60)

            ConversationCard(transcript: assistant.transcript, reply: assistant.reply, error: assistant.errorMessage, actions: assistant.lastActions)
                .frame(maxWidth: 620)
                .padding(.horizontal, 28)

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                TextField("Или напишите команду…", text: $assistant.typedCommand)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
                    .onSubmit { assistant.submitTypedCommand() }
                    .disabled(assistant.isBusy)
                MicButton(status: assistant.status) { assistant.micButtonTapped() }
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 28)

            Text("Нажмите на микрофон или удерживайте \(HotkeyManager.displayName). Нажатие во время ответа перебивает NOVA.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 20)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: assistant.pendingConfirmation)
    }
}

/// Распознанная фраза, ответ ассистента и выполненные действия.
struct ConversationCard: View {
    let transcript: String
    let reply: String
    let error: String?
    let actions: [String]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(transcript.isEmpty ? "Скажите, например: «Открой YouTube»" : transcript)
                        .foregroundStyle(transcript.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "person.wave.2.fill").foregroundStyle(Theme.cyan)
                }
                .font(.system(.body, design: .rounded))

                if !reply.isEmpty {
                    Divider().overlay(Color.white.opacity(0.08))
                    Label {
                        Text(reply)
                            .foregroundStyle(error == nil ? Theme.textPrimary : Theme.danger)
                            .textSelection(.enabled)
                    } icon: {
                        Image(systemName: error == nil ? "sparkles" : "exclamationmark.triangle.fill")
                            .foregroundStyle(error == nil ? Theme.violet : Theme.danger)
                    }
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if !actions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(actions, id: \.self) { action in
                            Text(action)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.easeOut(duration: 0.25), value: reply)
    }
}
