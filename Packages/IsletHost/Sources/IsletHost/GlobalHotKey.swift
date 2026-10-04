import Carbon.HIToolbox
import Foundation
import os

@MainActor
public final class GlobalHotKey {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Islet", category: "hotkey")

    private let onPress: @MainActor () -> Void
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var handlerRef: EventHandlerRef?

    public init(onPress: @escaping @MainActor () -> Void) {
        self.onPress = onPress
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    @discardableResult
    public func register(_ shortcut: NotchShortcut) -> Bool {
        unregister()
        guard let key = shortcut.carbonKey else { return true }
        guard installHandlerIfNeeded() else { return false }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: hotKeySignature, id: 1)
        let status = RegisterEventHotKey(key.code, key.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            Self.logger.error("Failed to register the shortcut \(shortcut.rawValue, privacy: .public): \(status)")
            return false
        }
        hotKeyRef = ref
        return true
    }

    fileprivate func pressed() {
        onPress()
    }

    private func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    private func installHandlerIfNeeded() -> Bool {
        guard handlerRef == nil else { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handleHotKeyEvent,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard status == noErr else {
            Self.logger.error("Failed to install the shortcut handler: \(status)")
            handlerRef = nil
            return false
        }
        return true
    }
}

private let hotKeySignature: OSType = 0x4953_4C54

private func handleHotKeyEvent(_ handler: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &id
    )
    guard status == noErr, id.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }
    let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        hotKey.pressed()
    }
    return noErr
}

extension NotchShortcut {
    var carbonKey: (code: UInt32, modifiers: UInt32)? {
        switch self {
        case .off: nil
        case .controlOptionSpace: (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        case .controlOptionN: (UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey))
        case .controlCommandN: (UInt32(kVK_ANSI_N), UInt32(controlKey | cmdKey))
        case .controlOptionI: (UInt32(kVK_ANSI_I), UInt32(controlKey | optionKey))
        }
    }
}
