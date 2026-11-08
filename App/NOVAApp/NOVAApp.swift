import SwiftUI
import NOVACore

@main
struct NOVAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let environment = AppEnvironment.shared

    var body: some Scene {
        WindowGroup("NOVA AI", id: WindowID.main) {
            MainView()
                .environment(environment.assistant)
                .environment(environment.settings)
                .frame(minWidth: 860, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Показать/скрыть плавающую панель") {
                    appDelegate.toggleFloatingPanel()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarView(togglePanel: { appDelegate.toggleFloatingPanel() })
                .environment(environment.assistant)
                .environment(environment.settings)
                .preferredColorScheme(.dark)
        } label: {
            Image(systemName: environment.assistant.status == .listening ? "waveform.circle.fill" : "sparkles")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(environment.assistant)
                .environment(environment.settings)
                .environment(environment.diagnostics)
                .preferredColorScheme(.dark)
        }
    }
}

enum WindowID {
    static let main = "main"
}
