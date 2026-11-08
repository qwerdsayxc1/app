import SwiftUI
import NOVACore

/// История команд и диалога с кнопкой очистки памяти.
struct HistorySidebar: View {
    @Environment(AssistantViewModel.self) private var assistant
    @State private var tab: Tab = .commands
    @State private var confirmClear = false

    enum Tab: String, CaseIterable, Identifiable {
        case commands = "Команды"
        case dialog = "Диалог"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("История")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    confirmClear = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Очистить память")
                .disabled(assistant.history.isEmpty && assistant.recentCommands.isEmpty)
            }

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    switch tab {
                    case .commands:
                        if assistant.recentCommands.isEmpty {
                            EmptyHistory()
                        }
                        ForEach(assistant.recentCommands) { command in
                            CommandRow(command: command) { assistant.submit(command.utterance) }
                        }
                    case .dialog:
                        if assistant.history.isEmpty {
                            EmptyHistory()
                        }
                        ForEach(assistant.history.reversed()) { message in
                            MessageRow(message: message)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
        }
        .confirmationDialog("Очистить всю память NOVA?", isPresented: $confirmClear) {
            Button("Очистить", role: .destructive) { assistant.clearMemory() }
        } message: {
            Text("Будут удалены история диалогов, последние команды и контекст разговора. Настройки и API-ключ сохранятся.")
        }
    }
}

private struct EmptyHistory: View {
    var body: some View {
        Text("Здесь появятся ваши команды.")
            .font(.callout)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 40)
    }
}

private struct CommandRow: View {
    let command: CommandRecord
    let repeatAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Image(systemName: command.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(command.succeeded ? Theme.mint : Theme.danger)
                Text(command.utterance)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button(action: repeatAction) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Повторить команду")
            }
            if !command.summary.isEmpty {
                Text(command.summary)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Text(command.date, style: .relative)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        let isUser = message.role == .user
        Text(message.text)
            .font(.callout)
            .foregroundStyle(Theme.textPrimary)
            .padding(10)
            .background(
                (isUser ? Theme.blue : Theme.violet).opacity(0.18),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            .textSelection(.enabled)
    }
}
