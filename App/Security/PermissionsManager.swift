import AppKit
import AVFoundation
import Speech
import ApplicationServices

/// Статус одного разрешения macOS.
enum PermissionState: Equatable {
    case granted
    case denied
    case notDetermined

    var title: String {
        switch self {
        case .granted: return "Разрешено"
        case .denied: return "Запрещено"
        case .notDetermined: return "Не запрошено"
        }
    }
}

/// Разрешения запрашиваются по мере необходимости и с объяснением (тексты — в Info.plist).
/// Права администратора не требуются ни для одного из них.
@MainActor
final class PermissionsManager {
    enum Pane: String {
        case microphone = "Privacy_Microphone"
        case speechRecognition = "Privacy_SpeechRecognition"
        case accessibility = "Privacy_Accessibility"
        case notifications = "Notifications"
    }

    var microphone: PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    var speechRecognition: PermissionState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Для Accessibility система не различает «не спрашивали» и «отказали».
    var accessibility: PermissionState {
        AXIsProcessTrusted() ? .granted : .notDetermined
    }

    /// Микрофон + распознавание речи. Бросает понятную ошибку, если пользователь отказал.
    func ensureVoicePermissions() async throws {
        switch microphone {
        case .granted:
            break
        case .denied:
            throw VoiceError.microphoneDenied
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw VoiceError.microphoneDenied }
        }
        switch speechRecognition {
        case .granted:
            break
        case .denied:
            throw VoiceError.speechRecognitionDenied
        case .notDetermined:
            guard await Self.requestSpeechAuthorization() == .authorized else { throw VoiceError.speechRecognitionDenied }
        }
    }

    /// Системный запрос «Универсального доступа» (нужен только для работы с окнами).
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openSystemSettings(_ pane: Pane) {
        let address: String
        switch pane {
        case .notifications:
            address = "x-apple.systempreferences:com.apple.preference.notifications"
        default:
            address = "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)"
        }
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }

    /// nonisolated: колбэк Speech приходит на произвольной очереди.
    private nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
