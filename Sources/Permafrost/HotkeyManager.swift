import AppKit
import Carbon.HIToolbox

/// Preset global shortcuts (ADR-005). All use V for Win+V muscle memory;
/// ⇧⌘V is deliberately absent — it collides with "Paste and Match Style".
enum HotkeyPreset: String, CaseIterable {
    case optionCommandV
    case controlCommandV
    case controlOptionV

    var keyCode: UInt32 { UInt32(kVK_ANSI_V) }

    var carbonModifiers: UInt32 {
        switch self {
        case .optionCommandV: UInt32(cmdKey | optionKey)
        case .controlCommandV: UInt32(cmdKey | controlKey)
        case .controlOptionV: UInt32(controlKey | optionKey)
        }
    }

    var display: String {
        switch self {
        case .optionCommandV: "⌥⌘V"
        case .controlCommandV: "⌃⌘V"
        case .controlOptionV: "⌃⌥V"
        }
    }
}

/// Carbon RegisterEventHotKey wrapper (ADR-005): the one reliable, native,
/// no-permission-needed way to own a global shortcut.
@MainActor
final class HotkeyManager {
    var onHotkey: () -> Void = {}

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register(preset: HotkeyPreset) {
        unregister()
        installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x5046_5254) /* 'PFRT' */, id: 1)
        let status = RegisterEventHotKey(
            preset.keyCode,
            preset.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            Log.app.error("hotkey registration failed: \(status)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                // Carbon dispatches on the main thread.
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData)
                    .takeUnretainedValue()
                MainActor.assumeIsolated {
                    manager.onHotkey()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
    }
}
