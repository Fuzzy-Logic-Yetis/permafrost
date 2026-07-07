import AppKit
import Carbon.HIToolbox
import IOKit.hid

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
