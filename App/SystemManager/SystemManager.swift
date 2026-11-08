import Foundation
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
