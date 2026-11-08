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

        static let setDarkMode = """
        on run argv
            tell application "System Events" to tell appearance preferences to set dark mode to ((item 1 of argv) is "true")
        end run
        """

        static let createReminder = """
        on run argv
            tell application "Reminders" to make new reminder with properties {name:(item 1 of argv)}
        end run
        """

        // Музыка: отдельные скрипты для каждого плеера — словари команд разные.
        static let musicControl = """
        on run argv
            set act to item 1 of argv
            tell application "Music"
                if act is "play" then
                    play
                else if act is "pause" then
                    pause
                else if act is "toggle" then
                    playpause
                else if act is "next" then
                    next track
                else if act is "previous" then
                    previous track
                end if
            end tell
        end run
        """

        static let spotifyControl = """
        on run argv
            set act to item 1 of argv
            tell application "Spotify"
                if act is "play" then
                    play
                else if act is "pause" then
                    pause
                else if act is "toggle" then
                    playpause
                else if act is "next" then
                    next track
                else if act is "previous" then
                    previous track
                end if
            end tell
        end run
        """

        /// "название||исполнитель||playing|paused|stopped"
        static let musicNowPlaying = """
        tell application "Music"
            if player state is stopped then return "||||stopped"
            set t to current track
            return (name of t) & "||" & (artist of t) & "||" & (player state as text)
        end tell
        """

        static let spotifyNowPlaying = """
        tell application "Spotify"
            if player state is stopped then return "||||stopped"
            return (name of current track) & "||" & (artist of current track) & "||" & (player state as text)
        end tell
        """

        static let safariTab = """
        on run argv
            set act to item 1 of argv
            tell application "Safari"
                activate
                if (count of windows) is 0 then
                    if act is "new_tab" then make new document
                    return
                end if
                if act is "new_tab" then
                    tell front window to set current tab to (make new tab)
                else if act is "close_tab" then
                    close current tab of front window
                else if act is "reload" then
                    set pageURL to URL of current tab of front window
                    set URL of current tab of front window to pageURL
                end if
            end tell
        end run
        """

        static let chromeTab = """
        on run argv
            set act to item 1 of argv
            tell application "Google Chrome"
                activate
                if (count of windows) is 0 then
                    if act is "new_tab" then make new window
                    return
                end if
                if act is "new_tab" then
                    make new tab at end of tabs of front window
                else if act is "close_tab" then
                    close active tab of front window
                else if act is "reload" then
                    reload active tab of front window
                end if
            end tell
        end run
        """
    }

    /// Разбирает вывод скриптов now playing.
    static func parseNowPlaying(_ output: String, player: String) -> NowPlaying? {
        let parts = output.components(separatedBy: "||")
        guard parts.count == 3, parts[2] != "stopped", !parts[0].isEmpty else { return nil }
        return NowPlaying(title: parts[0], artist: parts[1], player: player, isPlaying: parts[2] == "playing")
    }

    static func run(_ source: String, arguments: [String] = []) async throws -> String {
        try await ProcessRunner.run(executable: "/usr/bin/osascript", arguments: ["-e", source] + arguments)
    }
}

/// Запуск системной утилиты по абсолютному пути с фиксированными аргументами
/// (без shell, без подстановки строк). Используется для osascript, screencapture, pmset.
enum ProcessRunner {
    struct Output: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static func run(executable: String, arguments: [String]) async throws -> String {
        let output = try await execute(executable: executable, arguments: arguments)
        guard output.status == 0 else {
            let message = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let tool = (executable as NSString).lastPathComponent
            throw AutomationError.scriptFailed(message.isEmpty ? "\(tool) exit \(output.status)" : message)
        }
        return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func execute(executable: String, arguments: [String]) async throws -> Output {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Output, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
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
