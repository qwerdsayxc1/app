import AppKit
import NOVACore

/// Автоматическая самопроверка без Claude и без человека (запуск: `NOVA AI --self-test <папка>`).
/// Делает скриншоты интерфейса в разных состояниях, выполняет безопасные инструменты
/// на этом Mac и пишет отчёт (report.md, report.json). Используется в GitHub Actions.
@MainActor
final class SelfTestRunner {
    struct Entry {
        let tool: String
        let arguments: String
        let status: String
        let result: String
        let seconds: Double
    }

    private let output: URL
    private let environment: AppEnvironment
    private let togglePanel: () -> Void
    private var entries: [Entry] = []
    private var screenshots: [String] = []
    private var notes: [String] = []

    init(output: URL, environment: AppEnvironment, togglePanel: @escaping () -> Void) {
        self.output = output
        self.environment = environment
        self.togglePanel = togglePanel
    }

    func run() async {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        // Страховка: что бы ни случилось, через 5 минут приложение завершится.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300 * 1_000_000_000)
            self.notes.append("Global deadline reached")
            self.writeReport()
            NSApp.terminate(nil)
        }

        await captureInterface()
        await runTools()
        writeReport()
        NSApp.terminate(nil)
    }

    // MARK: - Интерфейс

    private func captureInterface() async {
        environment.settings.forceMainInterface = true
        NSApp.activate()
        await pause(2.0)

        let commands = [
            CommandRecord(utterance: "Открой YouTube", actions: ["✓ open_website"], summary: "Открыл YouTube в Safari.", succeeded: true, date: Date().addingTimeInterval(-600)),
            CommandRecord(utterance: "Сколько процентов батареи осталось?", actions: ["✓ get_battery_status"], summary: "82 процента, не заряжается.", succeeded: true, date: Date().addingTimeInterval(-420)),
            CommandRecord(utterance: "Выключи звук", actions: ["✓ set_mute"], summary: "Звук выключен.", succeeded: true, date: Date().addingTimeInterval(-300)),
            CommandRecord(utterance: "Какие окна открыты в Xcode?", actions: ["✗ list_windows"], summary: "Нужен доступ «Универсальный доступ».", succeeded: false, date: Date().addingTimeInterval(-120))
        ]
        let states: [(String, AssistantStatus, Float, String, String, [String])] = [
            ("1-idle", .idle, 0, "", "", []),
            ("2-listening", .listening, 0.7, "Найди на YouTube видео про Python", "", []),
            ("3-thinking", .thinking, 0, "Найди на YouTube видео про Python", "", []),
            ("4-speaking", .speaking, 0.4, "Найди на YouTube видео про Python", "Открыл на YouTube первое видео про Python.", ["✓ play_youtube_video {\"query\":\"видео про Python\"}"])
        ]
        for (name, status, level, transcript, reply, actions) in states {
            environment.assistant.applyDemoState(status: status, level: level, transcript: transcript, reply: reply, actions: actions, commands: commands)
            await pause(1.2)
            await captureVisibleWindows(prefix: "main-\(name)")
        }

        togglePanel()
        await pause(1.2)
        await captureVisibleWindows(prefix: "panel")
        togglePanel()

        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            await pause(1.5)
            await captureVisibleWindows(prefix: "settings")
        } else {
            notes.append("Settings window could not be opened programmatically")
        }

        // Полный экран (может быть пустым без разрешения «Запись экрана»).
        let full = output.appendingPathComponent("fullscreen.png")
        if (try? await ProcessRunner.run(executable: "/usr/sbin/screencapture", arguments: ["-x", full.path])) != nil {
            screenshots.append(full.lastPathComponent)
        }
        environment.assistant.applyDemoState(status: .idle, level: 0, transcript: "", reply: "", actions: [], commands: [])
    }

    /// Каждое видимое окно снимается двумя способами: рендер содержимого (без разрешений)
    /// и screencapture по номеру окна.
    private func captureVisibleWindows(prefix: String) async {
        let windows = NSApp.windows.filter { $0.isVisible && $0.frame.width > 120 && $0.frame.height > 80 }
        for (index, window) in windows.enumerated() {
            let base = windows.count == 1 ? prefix : "\(prefix)-\(index + 1)"
            if let view = window.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if let data = rep.representation(using: .png, properties: [:]) {
                    let url = output.appendingPathComponent("\(base)-render.png")
                    if (try? data.write(to: url)) != nil { screenshots.append(url.lastPathComponent) }
                }
            }
            let shot = output.appendingPathComponent("\(base)-window.png")
            if (try? await ProcessRunner.run(executable: "/usr/sbin/screencapture", arguments: ["-x", "-o", "-l", String(window.windowNumber), shot.path])) != nil,
               FileManager.default.fileExists(atPath: shot.path) {
                screenshots.append(shot.lastPathComponent)
            }
        }
    }

    // MARK: - Инструменты

    private func runTools() async {
        for call in ToolSamples.selfTestSequence {
            let started = Date()
            let record = await execute(call, timeout: 20)
            let seconds = (Date().timeIntervalSince(started) * 10).rounded() / 10
            if let record {
                entries.append(Entry(tool: call.name, arguments: call.input.compactString(), status: record.result.isError ? "error" : "ok", result: record.result.content, seconds: seconds))
            } else {
                entries.append(Entry(tool: call.name, arguments: call.input.compactString(), status: "timeout", result: "No answer in 20 s (probably waiting for a system permission dialog).", seconds: seconds))
            }
            await pause(0.5)
        }
    }

    /// Выполнение с тайм-аутом: зависший системный диалог не должен блокировать проверку.
    private func execute(_ call: ToolCall, timeout: TimeInterval) async -> ToolExecutionRecord? {
        let toolManager = environment.toolManager
        return await withCheckedContinuation { (continuation: CheckedContinuation<ToolExecutionRecord?, Never>) in
            let once = OnceFlag()
            Task { @MainActor in
                let record = await toolManager.execute(call)
                if once.fire() { continuation.resume(returning: record) }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if once.fire() { continuation.resume(returning: nil) }
            }
        }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - Отчёт

    private func writeReport() {
        let permissions = environment.permissions
        let ok = entries.filter { $0.status == "ok" }.count
        var markdown = """
        # NOVA AI — самопроверка

        - macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        - Инструменты: \(ok) из \(entries.count) выполнены успешно
        - Микрофон: \(permissions.microphone.title) · Распознавание речи: \(permissions.speechRecognition.title) · Универсальный доступ: \(permissions.accessibility.title)
        - Скриншоты: \(screenshots.count)

        | Инструмент | Статус | Время, с | Результат |
        |---|---|---|---|

        """
        for entry in entries {
            let icon = entry.status == "ok" ? "✅" : (entry.status == "timeout" ? "⏱" : "❌")
            let result = entry.result.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ")
            markdown += "| `\(entry.tool)` | \(icon) \(entry.status) | \(entry.seconds) | \(result.prefix(220)) |\n"
        }
        if !notes.isEmpty {
            markdown += "\n## Заметки\n" + notes.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        markdown += "\n## Файлы скриншотов\n" + screenshots.map { "- \($0)" }.joined(separator: "\n") + "\n"
        try? markdown.write(to: output.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)

        let json = JSONValue.array(entries.map {
            ["tool": .string($0.tool), "arguments": .string($0.arguments), "status": .string($0.status), "result": .string($0.result), "seconds": .number($0.seconds)]
        })
        if let data = try? json.encodedData() {
            try? data.write(to: output.appendingPathComponent("report.json"))
        }
    }
}

@MainActor
private final class OnceFlag {
    private var fired = false
    func fire() -> Bool {
        guard !fired else { return false }
        fired = true
        return true
    }
}
