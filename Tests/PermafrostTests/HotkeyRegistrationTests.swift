import Carbon.HIToolbox
import Testing

@testable import Permafrost

@MainActor
@Suite struct HotkeyRegistrationTests {
    @Test func successfulRegistrationKeepsConfiguredCustomShortcut() {
        let original = HotkeyPreset.optionCommandV.shortcut
        let custom = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_H), carbonModifiers: UInt32(controlKey | optionKey))
        let settings = FakeHotkeySettings(customHotkey: custom, preset: .optionCommandV)
        let registrar = FakeHotkeyRegistrar(results: [true])
        let coordinator = HotkeyRegistrationCoordinator(settings: settings, registrar: registrar)

        let result = coordinator.registerEffectiveHotkey()

        #expect(result == true)
        #expect(settings.customHotkey == custom)
        #expect(registrar.registeredShortcuts == [custom])
        #expect(settings.effectiveHotkey != original)
    }

    @Test func failedCustomRegistrationRestoresPreviousWorkingCustomShortcutAndReportsFailure() {
        let previousCustom = HotkeyShortcut(
            keyCode: UInt32(kVK_ANSI_J),
            carbonModifiers: UInt32(controlKey | optionKey)
        )
        let rejectedCustom = HotkeyShortcut(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(controlKey | optionKey)
        )
        let settings = FakeHotkeySettings(customHotkey: previousCustom, preset: .optionCommandV)
        let registrar = FakeHotkeyRegistrar(results: [true, false, true])
        let coordinator = HotkeyRegistrationCoordinator(settings: settings, registrar: registrar)
        var failedDisplays: [String] = []

        #expect(coordinator.registerEffectiveHotkey(onFailure: { failedDisplays.append($0) }) == true)
        settings.customHotkey = rejectedCustom

        let result = coordinator.registerEffectiveHotkey(onFailure: { failedDisplays.append($0) })

        #expect(result == false)
        #expect(settings.customHotkey == previousCustom)
        #expect(registrar.registeredShortcuts == [previousCustom, rejectedCustom, previousCustom])
        #expect(failedDisplays == [rejectedCustom.display])
    }

    @Test func failedFirstCustomRegistrationFallsBackToSelectedPresetAndReportsFailure() {
        let rejectedCustom = HotkeyShortcut(
            keyCode: UInt32(kVK_ANSI_L),
            carbonModifiers: UInt32(controlKey | optionKey)
        )
        let settings = FakeHotkeySettings(customHotkey: rejectedCustom, preset: .controlCommandV)
        let registrar = FakeHotkeyRegistrar(results: [false, true])
        let coordinator = HotkeyRegistrationCoordinator(settings: settings, registrar: registrar)
        var failedDisplays: [String] = []

        let result = coordinator.registerEffectiveHotkey(onFailure: { failedDisplays.append($0) })

        #expect(result == false)
        #expect(settings.customHotkey == nil)
        #expect(settings.effectiveHotkey == HotkeyPreset.controlCommandV.shortcut)
        #expect(registrar.registeredShortcuts == [rejectedCustom, HotkeyPreset.controlCommandV.shortcut])
        #expect(failedDisplays == [rejectedCustom.display])
    }
}

@MainActor
private final class FakeHotkeySettings: HotkeySettingsStore {
    var customHotkey: HotkeyShortcut?
    var preset: HotkeyPreset

    init(customHotkey: HotkeyShortcut?, preset: HotkeyPreset) {
        self.customHotkey = customHotkey
        self.preset = preset
    }

    var effectiveHotkey: HotkeyShortcut {
        customHotkey ?? preset.shortcut
    }

    var hotkeyDisplay: String {
        effectiveHotkey.display
    }
}

@MainActor
private final class FakeHotkeyRegistrar: HotkeyRegistering {
    private var results: [Bool]
    private(set) var registeredShortcuts: [HotkeyShortcut] = []

    init(results: [Bool]) {
        self.results = results
    }

    func register(shortcut: HotkeyShortcut) -> Bool {
        registeredShortcuts.append(shortcut)
        return results.isEmpty ? true : results.removeFirst()
    }
}
