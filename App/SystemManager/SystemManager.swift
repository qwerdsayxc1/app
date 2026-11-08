import AppKit
import IOKit.ps
import NOVACore

/// Системная информация и звук. Права администратора не нужны.
@MainActor
final class SystemManager: SystemManaging {
    // MARK: Звук (AppleScript Standard Additions, без Apple Events к другим приложениям)

    func volume() async throws -> VolumeState {
        let output = try await AppleScriptRunner.run(AppleScriptRunner.Script.getVolume)
        guard let state = Self.parseVolume(output) else {
            throw AutomationError.scriptFailed("The current output device does not report a volume level.")
        }
        return state
    }

    func setVolume(_ level: Int) async throws {
        let clamped = min(100, max(0, level))
        _ = try await AppleScriptRunner.run(AppleScriptRunner.Script.setVolume, arguments: [String(clamped)])
    }

    func setMuted(_ muted: Bool) async throws {
        _ = try await AppleScriptRunner.run(AppleScriptRunner.Script.setMuted, arguments: [muted ? "true" : "false"])
    }

    /// "40,false" → VolumeState. "missing value" (например, HDMI-выход) → nil.
    static func parseVolume(_ output: String) -> VolumeState? {
        let parts = output.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let level = Int(parts[0]) else { return nil }
        return VolumeState(level: level, isMuted: parts[1] == "true")
    }

    // MARK: Батарея (IOKit Power Sources)

    func batteryStatus() throws -> BatteryStatus {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            throw AutomationError.batteryUnavailable
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let isOnAC = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let timeToEmpty = description[kIOPSTimeToEmptyKey] as? Int
            return BatteryStatus(
                percent: min(100, max(0, percent)),
                isCharging: isCharging,
                isOnACPower: isOnAC,
                minutesRemaining: (timeToEmpty ?? -1) > 0 && !isOnAC ? timeToEmpty : nil
            )
        }
        throw AutomationError.batteryUnavailable
    }

    // MARK: Диск

    func diskSpace() throws -> DiskSpace {
        let root = URL(fileURLWithPath: "/")
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return DiskSpace(
            availableBytes: values.volumeAvailableCapacityForImportantUsage ?? 0,
            totalBytes: Int64(values.volumeTotalCapacity ?? 0)
        )
    }

    // MARK: Информация о системе

    func systemInfo() -> SystemInfo {
        let process = ProcessInfo.processInfo
        let version = process.operatingSystemVersion
        return SystemInfo(
            osVersion: "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            modelIdentifier: Self.sysctlString("hw.model") ?? "Mac",
            chip: Self.sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon",
            memoryBytes: process.physicalMemory,
            cpuCores: process.activeProcessorCount,
            uptimeSeconds: process.systemUptime
        )
    }

    // MARK: Оформление, экран, снимки, папки

    /// Требует разрешения «Автоматизация → System Events» (macOS спросит один раз).
    func setDarkMode(_ enabled: Bool) async throws {
        _ = try await AppleScriptRunner.run(AppleScriptRunner.Script.setDarkMode, arguments: [enabled ? "true" : "false"])
    }

    /// `pmset displaysleepnow` работает без прав администратора.
    func sleepDisplay() async throws {
        _ = try await ProcessRunner.run(executable: "/usr/bin/pmset", arguments: ["displaysleepnow"])
    }

    /// Снимок всего экрана на Рабочий стол. Нужен доступ «Запись экрана»; файл никуда не отправляется.
    func takeScreenshot() async throws -> URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let file = desktop.appendingPathComponent("NOVA Screenshot \(formatter.string(from: Date())).png")
        // -x: без звука затвора. Путь передаётся отдельным аргументом, не через shell.
        _ = try await ProcessRunner.run(executable: "/usr/sbin/screencapture", arguments: ["-x", file.path])
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw AutomationError.scriptFailed("Screenshot was not saved. Allow NOVA AI in System Settings › Privacy & Security › Screen Recording.")
        }
        return file
    }

    func openFolder(_ folder: StandardFolder) throws -> URL {
        let fileManager = FileManager.default
        let url: URL?
        switch folder {
        case .home: url = fileManager.homeDirectoryForCurrentUser
        case .desktop: url = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
        case .documents: url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        case .downloads: url = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
        case .applications: url = URL(fileURLWithPath: "/Applications")
        case .pictures: url = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
        case .music: url = fileManager.urls(for: .musicDirectory, in: .userDomainMask).first
        case .movies: url = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first
        }
        guard let url, NSWorkspace.shared.open(url) else {
            throw AutomationError.scriptFailed("Could not open folder \(folder.rawValue).")
        }
        return url
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let value = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
