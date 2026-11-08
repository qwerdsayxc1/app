import Carbon.HIToolbox
import Foundation

/// Глобальная горячая клавиша push-to-talk (по умолчанию ⌥Space).
/// Carbon `RegisterEventHotKey` не требует разрешения «Универсальный доступ»
/// и не перехватывает остальные нажатия клавиатуры.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var isPressed = false

    private init() {}

    /// keyCode — виртуальный код клавиши (kVK_*), modifiers — Carbon-модификаторы (optionKey, cmdKey…).
    func register(keyCode: UInt32 = UInt32(kVK_Space), modifiers: UInt32 = UInt32(optionKey)) {
        unregister()

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        // C-колбэк без захвата контекста; события доставляются на главный поток.
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                let kind = GetEventKind(event)
                Task { @MainActor in HotkeyManager.shared.handle(kind: kind) }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            nil,
            &handlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x4E4F_5641), id: 1) // 'NOVA'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        isPressed = false
    }

    private func handle(kind: UInt32) {
        switch Int(kind) {
        case kEventHotKeyPressed:
            guard !isPressed else { return } // автоповтор клавиши
            isPressed = true
            onPress?()
        case kEventHotKeyReleased:
            isPressed = false
            onRelease?()
        default:
            break
        }
    }

    static let displayName = "⌥ Space"
}
