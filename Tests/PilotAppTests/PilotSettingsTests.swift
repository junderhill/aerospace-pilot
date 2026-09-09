import Foundation
import Testing
import Carbon
import PilotCore
@testable import PilotApp

@MainActor struct PilotSettingsTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "AeroSpacePilotTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func exclusionsAndShortcutPersistAcrossInstances() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = PilotSettings(defaults: defaults)
        #expect(settings.excludedBundleIDs.isEmpty)
        settings.setExcluded("com.openai.codex", enabled: true)
        settings.setExcluded("com.openai.codex", enabled: false)
        settings.setExcluded("com.example.notes", enabled: true)
        #expect(!settings.hasSeededWork)
        settings.markWorkSeeded()
        settings.quickViewShortcut = QuickViewShortcut(keyCode: 0, modifiers: UInt32(cmdKey), keyName: "A")

        let restored = PilotSettings(defaults: defaults)
        #expect(restored.excludedBundleIDs == ["com.example.notes"])
        #expect(restored.hasSeededWork)
        #expect(restored.effectiveExcludedBundleIDs.contains(Protection.pilot))
        #expect(restored.quickViewShortcut.displayLabel == "⌘A")
    }

    @Test func immutablePilotCannotBeAddedOrRemoved() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = PilotSettings(defaults: defaults)
        settings.setExcluded(Protection.pilot, enabled: false)
        #expect(!settings.addExcluded(Protection.pilot))
        #expect(!settings.excludedBundleIDs.contains(Protection.pilot))
        #expect(settings.effectiveExcludedBundleIDs.contains(Protection.pilot))
    }

    @Test func customBundleIDsNeedBundleIdentifierShape() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = PilotSettings(defaults: defaults)
        #expect(settings.addExcluded("not-an-id") == false)
        #expect(settings.addExcluded("com.example.notes"))
    }
}
