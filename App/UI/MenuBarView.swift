import AppKit
import SwiftUI
import NOVACore

/// Окно иконки в строке меню (MenuBarExtra).
struct MenuBarView: View {
    @Environment(AssistantViewModel.self) private var assistant
    @Environment(\.openWindow) private var openWindow
    let togglePanel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                OrbView(status: assistant.status, level: assistant.audioLevel, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NOVA AI").font(.headline)
                    Text(assistant.status.title)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                MicButton(status: assistant.status, size: 40) { assistant.micButtonTapped() }
            }

            if !assistant.reply.isEmpty || !assistant.transcript.isEmpty {
                Text(assistant.reply.isEmpty ? assistant.transcript : assistant.reply)
                    .font(.callout)
                    .lineLimit(3)
                    .foregroundStyle(Theme.textPrimary)
            }

            if let request = assistant.pendingConfirmation {
                ConfirmationBanner(request: request) { assistant.resolveConfirmation($0) }
            }

            Divider()

            Button {
                openWindow(id: WindowID.main)
                NSApp.activate()
            } label: {
                Label("Открыть NOVA", systemImage: "macwindow")
            }
            Button(action: togglePanel) {
                Label("Плавающая панель", systemImage: "rectangle.on.rectangle")
            }
            SettingsLink {
                Label("Настройки…", systemImage: "gearshape")
            }
            Divider()
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("Выйти из NOVA", systemImage: "power")
            }
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 300)
    }
}
