import AppKit
import SwiftUI
import NOVACore

/// Компактная плавающая панель поверх всех окон (NSPanel, не забирает фокус у текущего приложения).
@MainActor
final class FloatingPanelController {
    private let panel: NSPanel

    init(assistant: AssistantViewModel, settings: SettingsViewModel) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 132),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let content = CompactPanelView()
            .environment(assistant)
            .environment(settings)
            .preferredColorScheme(.dark)
        panel.contentView = NSHostingView(rootView: content)
        self.panel = panel
        positionTopRight()
    }

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func positionTopRight() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let origin = NSPoint(x: frame.maxX - panel.frame.width - 24, y: frame.maxY - panel.frame.height - 24)
        panel.setFrameOrigin(origin)
    }
}

/// Содержимое плавающей панели: мини-Orb, статус, последняя фраза/ответ, микрофон.
struct CompactPanelView: View {
    @Environment(AssistantViewModel.self) private var assistant

    var body: some View {
        HStack(spacing: 14) {
            OrbView(status: assistant.status, level: assistant.audioLevel, size: 72)
                .onTapGesture { assistant.micButtonTapped() }
            VStack(alignment: .leading, spacing: 6) {
                StatusBadge(status: assistant.status)
                    .scaleEffect(0.85, anchor: .leading)
                if let request = assistant.pendingConfirmation {
                    Text(request.prompt)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                        .lineLimit(2)
                    HStack {
                        Button("Нет") { assistant.resolveConfirmation(false) }
                        Button("Да") { assistant.resolveConfirmation(true) }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.danger)
                    }
                    .controlSize(.small)
                } else {
                    Text(displayText)
                        .font(.callout)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    WaveformView(status: assistant.status, level: assistant.audioLevel)
                        .frame(height: 22)
                }
            }
            Spacer(minLength: 0)
            MicButton(status: assistant.status, size: 44) { assistant.micButtonTapped() }
        }
        .padding(16)
        .frame(width: 340, height: 132)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.accentGradient.opacity(0.5), lineWidth: 1)
        )
    }

    private var displayText: String {
        if !assistant.reply.isEmpty { return assistant.reply }
        if !assistant.transcript.isEmpty { return assistant.transcript }
        return "Удерживайте \(HotkeyManager.displayName) и говорите"
    }
}
