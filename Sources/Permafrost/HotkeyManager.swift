import AppKit
import Carbon.HIToolbox
import IOKit.hid

struct HotkeyShortcut: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    var display: String {
        HotkeyShortcut.modifierDisplay(carbonModifiers) + HotkeyShortcut.keyDisplay(keyCode)
    }

    var isValidGlobalShortcut: Bool {
        let primaryModifiers = UInt32(cmdKey | optionKey | controlKey)
        return carbonModifiers & primaryModifiers != 0
    }

    static func fromEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> HotkeyShortcut? {
        var carbonModifiers: UInt32 = 0
        if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

        let shortcut = HotkeyShortcut(keyCode: UInt32(keyCode), carbonModifiers: carbonModifiers)
        guard shortcut.isValidGlobalShortcut else { return nil }
        return shortcut
    }

    private static func modifierDisplay(_ modifiers: UInt32) -> String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result
    }

    private static func keyDisplay(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: "A"
        case kVK_ANSI_B: "B"
        case kVK_ANSI_C: "C"
        case kVK_ANSI_D: "D"
        case kVK_ANSI_E: "E"
        case kVK_ANSI_F: "F"
        case kVK_ANSI_G: "G"
        case kVK_ANSI_H: "H"
        case kVK_ANSI_I: "I"
        case kVK_ANSI_J: "J"
        case kVK_ANSI_K: "K"
        case kVK_ANSI_L: "L"
        case kVK_ANSI_M: "M"
        case kVK_ANSI_N: "N"
        case kVK_ANSI_O: "O"
        case kVK_ANSI_P: "P"
        case kVK_ANSI_Q: "Q"
        case kVK_ANSI_R: "R"
        case kVK_ANSI_S: "S"
        case kVK_ANSI_T: "T"
        case kVK_ANSI_U: "U"
        case kVK_ANSI_V: "V"
        case kVK_ANSI_W: "W"
        case kVK_ANSI_X: "X"
        case kVK_ANSI_Y: "Y"
        case kVK_ANSI_Z: "Z"
        case kVK_ANSI_0: "0"
        case kVK_ANSI_1: "1"
        case kVK_ANSI_2: "2"
        case kVK_ANSI_3: "3"
        case kVK_ANSI_4: "4"
        case kVK_ANSI_5: "5"
        case kVK_ANSI_6: "6"
        case kVK_ANSI_7: "7"
        case kVK_ANSI_8: "8"
        case kVK_ANSI_9: "9"
        case kVK_Space: "Space"
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        case kVK_Delete: "⌫"
        case kVK_Escape: "Esc"
        case kVK_F1: "F1"
        case kVK_F2: "F2"
        case kVK_F3: "F3"
        case kVK_F4: "F4"
        case kVK_F5: "F5"
        case kVK_F6: "F6"
        case kVK_F7: "F7"
        case kVK_F8: "F8"
        case kVK_F9: "F9"
        case kVK_F10: "F10"
        case kVK_F11: "F11"
        case kVK_F12: "F12"
        default: "Key \(keyCode)"
        }
    }
}

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

    var shortcut: HotkeyShortcut {
        HotkeyShortcut(keyCode: keyCode, carbonModifiers: carbonModifiers)
    }
}

/// Carbon RegisterEventHotKey wrapper (ADR-005). ADR-005 originally assumed this
/// needs no permission at all — true for the hotkey firing, but ADR-014 found
/// this OS also silently checks Input Monitoring (`kTCCServiceListenEvent`)
/// around app launch, denies it with no prompt if never explicitly requested,
/// and the status item can end up invisible as a result. See
/// `requestInputMonitoringAccessIfNeeded()` below.
@MainActor
final class HotkeyManager {
    var onHotkey: () -> Void = {}

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// For Settings' permission status display (ADR-016).
    static var isInputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Explicitly requests Input Monitoring access via the official IOHID API —
    /// this triggers a normal system Allow/Don't Allow prompt (no password
    /// needed, unlike manually adding an app via System Settings' "+" button).
    /// Call once at startup, before registering the hotkey (ADR-014).
    static func requestInputMonitoringAccessIfNeeded() {
        let accessType = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        switch accessType {
        case kIOHIDAccessTypeGranted:
            Log.app.info("Input Monitoring already granted")
        case kIOHIDAccessTypeDenied:
            Log.app.error(
                "Input Monitoring denied — enable in System Settings > Privacy & Security > Input Monitoring, then relaunch Permafrost"
            )
        default:
            let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            Log.app.info("Input Monitoring access requested; granted: \(granted)")
        }
    }

    @discardableResult
    func register(preset: HotkeyPreset) -> Bool {
        register(shortcut: preset.shortcut)
    }

    /// Returns whether Carbon actually accepted the shortcut (review M-1): a
    /// reserved or already-claimed combination fails registration but was
    /// previously reported to the caller as if it succeeded.
    @discardableResult
    func register(shortcut: HotkeyShortcut) -> Bool {
        unregister()
        installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x5046_5254) /* 'PFRT' */, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            Log.app.error("hotkey registration failed: \(status)")
            return false
        }
        return true
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
