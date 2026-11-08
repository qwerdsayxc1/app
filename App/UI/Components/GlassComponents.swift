import SwiftUI
import NOVACore

/// Стеклянная карточка (glassmorphism): материал + градиентная обводка + тень.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.22), Theme.violet.opacity(0.25), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.45), radius: 18, y: 10)
    }
}

/// Индикатор состояния: Idle / Listening / Thinking / Executing / Speaking.
struct StatusBadge: View {
    let status: AssistantStatus

    var body: some View {
        let (primary, _) = Theme.colors(for: status)
        HStack(spacing: 8) {
            Circle()
                .fill(primary)
                .frame(width: 8, height: 8)
                .shadow(color: primary, radius: 6)
                .phaseAnimator([0.4, 1.0]) { dot, phase in
                    dot.opacity(status == .idle ? 1 : phase)
                } animation: { _ in .easeInOut(duration: 0.7) }
            Text(status.title)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(primary.opacity(0.45), lineWidth: 1))
        .animation(.easeInOut(duration: 0.25), value: status)
        .accessibilityLabel("Статус: \(status.title)")
    }
}

/// Круглая кнопка микрофона со свечением. Нажатие — начать/закончить, во время ответа — перебить.
struct MicButton: View {
    let status: AssistantStatus
    var size: CGFloat = 72
    let action: () -> Void

    var body: some View {
        let isListening = status == .listening
        let (primary, secondary) = Theme.colors(for: status)
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: primary.opacity(0.8), radius: isListening ? 24 : 12)
                Image(systemName: symbol)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: size, height: size)
            .scaleEffect(isListening ? 1.08 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isListening)
        }
        .buttonStyle(.plain)
        .help("Нажмите, чтобы говорить. Горячая клавиша: удерживайте \(HotkeyManager.displayName).")
        .accessibilityLabel(isListening ? "Закончить запись" : "Начать запись")
    }

    private var symbol: String {
        switch status {
        case .listening: return "stop.fill"
        case .speaking, .thinking, .executing: return "hand.raised.fill"
        case .idle: return "mic.fill"
        }
    }
}

/// Плашка подтверждения опасного действия.
struct ConfirmationBanner: View {
    let request: ConfirmationRequest
    let onAnswer: (Bool) -> Void

    var body: some View {
        GlassCard(cornerRadius: 16, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Требуется подтверждение", systemImage: "exclamationmark.shield.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.danger)
                Text(request.prompt)
                    .foregroundStyle(Theme.textPrimary)
                Text("Ответьте голосом «да»/«нет» или кнопкой.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                HStack {
                    Button("Отмена", role: .cancel) { onAnswer(false) }
                        .keyboardShortcut(.escape, modifiers: [])
                    Spacer()
                    Button("Подтвердить") { onAnswer(true) }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.danger)
                }
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
