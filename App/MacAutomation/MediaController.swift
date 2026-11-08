import AppKit
import NOVACore

/// Управление музыкой в Apple Music и Spotify через их AppleScript-словари.
/// macOS один раз спросит разрешение «NOVA AI хочет управлять Music/Spotify».
@MainActor
final class MediaController: MediaControlling {
    static let musicBundleID = "com.apple.Music"
    static let spotifyBundleID = "com.spotify.client"

    func perform(_ action: MediaAction, player: MediaPlayer) async throws -> String {
        let target = resolve(player)
        let (bundleID, name, script) = target == .spotify
            ? (Self.spotifyBundleID, "Spotify", AppleScriptRunner.Script.spotifyControl)
            : (Self.musicBundleID, "Music", AppleScriptRunner.Script.musicControl)

        guard WorkspaceLauncher.applicationURL(bundleIdentifiers: [bundleID]) != nil else {
            throw AutomationError.playerNotAvailable(name)
        }
        // Пауза/переключение трека не должны запускать закрытый плеер — только «play».
        guard action == .play || isRunning(bundleID) else {
            throw AutomationError.playerNotAvailable(name)
        }
        _ = try await AppleScriptRunner.run(script, arguments: [action.rawValue])
        return name
    }

    func nowPlaying() async throws -> NowPlaying? {
        var results: [NowPlaying] = []
        // Опрашиваем только запущенные плееры, чтобы не запускать их.
        if isRunning(Self.spotifyBundleID) {
            let output = try await AppleScriptRunner.run(AppleScriptRunner.Script.spotifyNowPlaying)
            if let track = AppleScriptRunner.parseNowPlaying(output, player: "Spotify") { results.append(track) }
        }
        if isRunning(Self.musicBundleID) {
            let output = try await AppleScriptRunner.run(AppleScriptRunner.Script.musicNowPlaying)
            if let track = AppleScriptRunner.parseNowPlaying(output, player: "Music") { results.append(track) }
        }
        return results.first(where: \.isPlaying) ?? results.first
    }

    private func resolve(_ player: MediaPlayer) -> MediaPlayer {
        guard player == .auto else { return player }
        return isRunning(Self.spotifyBundleID) ? .spotify : .music
    }

    private func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}
