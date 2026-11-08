import Foundation
import NOVACore

/// Выполняет ТОЛЬКО фиксированные AppleScript-сценарии из этого файла через `/usr/bin/osascript`.
/// Пользовательские/модельные данные передаются исключительно как аргументы (`on run argv`),
/// никогда не подставляются в текст скрипта — это исключает инъекции.
/// Процесс запускается вне главного потока, UI не блокируется.
enum AppleScriptRunner {
    enum Script {
        /// Возвращает "громкость,muted", например "40,false".
        static let getVolume = """
        set s to get volume settings
        return ((output volume of s) as text) & "," & ((output muted of s) as text)
        """

        static let setVolume = """
        on run argv
            set volume output volume ((item 1 of argv) as integer)
        end run
        """

        static let setMuted = """
        on run argv
            if (item 1 of argv) is "true" then
                set volume with output muted
            else
                set volume without output muted
            end if
        end run
        """
    }

    struct Output: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static func run(_ source: String, arguments: [String] = []) async throws -> String {
        let output = try await execute(source: source, arguments: arguments)
        guard output.status == 0 else {
            let message = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AutomationError.scriptFailed(message.isEmpty ? "osascript exit \(output.status)" : message)
        }
        return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func execute(source: String, arguments: [String]) async throws -> Output {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Output, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source] + arguments
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            let stdoutHandle = stdoutPipe.fileHandleForReading
            let stderrHandle = stderrPipe.fileHandleForReading

            process.terminationHandler = { finished in
                // Вывод этих скриптов — единицы байт, буфер пайпа не переполняется.
                let out = String(data: stdoutHandle.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: stderrHandle.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: Output(status: finished.terminationStatus, stdout: out, stderr: err))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: AutomationError.scriptFailed(error.localizedDescription))
            }
        }
    }
}
