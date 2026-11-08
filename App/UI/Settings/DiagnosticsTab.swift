import SwiftUI
import NOVACore

/// Вкладка «Проверка»: всё, что можно проверить без API-ключа.
struct DiagnosticsTab: View {
    @Environment(DiagnosticsViewModel.self) private var model

    var body: some View {
        Form {
            Section {
                Text("Здесь NOVA работает без Claude и без API-ключа: можно проверить микрофон, голос и каждое действие по отдельности. Действия выполняются на этом Mac по-настоящему.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Голос") {
                HStack {
                    Button {
                        Task { await model.toggleRecording() }
                    } label: {
                        Label(model.isRecording ? "Остановить и распознать" : "Записать фразу", systemImage: model.isRecording ? "stop.circle.fill" : "mic.circle")
                    }
                    Button {
                        Task { await model.speakSample() }
                    } label: {
                        Label(model.isSpeaking ? "Остановить" : "Проверить озвучку", systemImage: "speaker.wave.2")
                    }
                }
                if !model.voiceTranscript.isEmpty {
                    LabeledContent("Распознано") {
                        Text(model.voiceTranscript).textSelection(.enabled)
                    }
                }
                if let error = model.voiceError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                ForEach(model.tools, id: \.name) { definition in
                    DiagnosticsToolRow(definition: definition)
                }
            } header: {
                HStack {
                    Text("Действия (\(model.tools.count))")
                    Spacer()
                    if !model.outcomes.isEmpty {
                        Text("✅ \(model.successCount)  ❌ \(model.errorCount)")
                        Button("Сбросить") { model.clearResults() }
                            .buttonStyle(.borderless)
                    }
                }
            } footer: {
                Text("«Закрыть приложение» спросит подтверждение, как и при голосовой команде. Некоторые действия при первом запуске попросят разрешение macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DiagnosticsToolRow: View {
    @Environment(DiagnosticsViewModel.self) private var model
    let definition: ToolDefinition

    var body: some View {
        let outcome = model.outcomes[definition.name]
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(definition.name.rawValue)
                    .font(.system(.body, design: .monospaced))
                if definition.risk == .requiresConfirmation {
                    Image(systemName: "exclamationmark.shield")
                        .foregroundStyle(.orange)
                        .help("Требует подтверждения")
                }
                Spacer()
                if model.runningTool == definition.name {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Запустить") {
                        Task { await model.run(definition.name) }
                    }
                    .disabled(model.runningTool != nil)
                }
            }
            Text(model.sampleText(for: definition.name))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let outcome {
                Text("\(outcome.isError ? "❌" : "✅") \(outcome.text)  ·  \(String(format: "%.1f", outcome.seconds)) с")
                    .font(.caption)
                    .foregroundStyle(outcome.isError ? .red : .green)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }
}
