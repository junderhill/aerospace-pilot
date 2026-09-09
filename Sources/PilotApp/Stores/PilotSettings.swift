import Foundation
import Observation
import PilotCore

@MainActor @Observable final class PilotSettings {
    private enum Key {
        static let excludedBundleIDs = "settings.excludedBundleIDs"
        static let quickViewShortcut = "settings.quickViewShortcut"
        static let hasSeededWork = "settings.hasSeededWork"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var excludedBundleIDs: Set<String> {
        didSet { persistExcludedBundleIDs() }
    }

    var quickViewShortcut: QuickViewShortcut {
        didSet { persistShortcut() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.excludedBundleIDs = Set(
            defaults.stringArray(forKey: Key.excludedBundleIDs) ?? []
        )
        if let data = defaults.data(forKey: Key.quickViewShortcut),
           let shortcut = try? JSONDecoder().decode(QuickViewShortcut.self, from: data) {
            self.quickViewShortcut = shortcut
        } else {
            self.quickViewShortcut = .defaultConfiguration
        }
    }

    var effectiveExcludedBundleIDs: Set<String> {
        excludedBundleIDs.union(Protection.immutable)
    }

    var hasSeededWork: Bool {
        defaults.bool(forKey: Key.hasSeededWork)
    }

    func markWorkSeeded() {
        defaults.set(true, forKey: Key.hasSeededWork)
    }

    func setExcluded(_ bundleID: String, enabled: Bool) {
        guard !Protection.immutable.contains(bundleID) else { return }
        if enabled {
            excludedBundleIDs.insert(bundleID)
        } else {
            excludedBundleIDs.remove(bundleID)
        }
    }

    @discardableResult
    func addExcluded(_ rawBundleID: String) -> Bool {
        let bundleID = rawBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard bundleID.contains("."), !bundleID.contains(where: \.isWhitespace),
              !Protection.immutable.contains(bundleID) else { return false }
        excludedBundleIDs.insert(bundleID)
        return true
    }

    private func persistExcludedBundleIDs() {
        defaults.set(excludedBundleIDs.sorted(), forKey: Key.excludedBundleIDs)
    }

    private func persistShortcut() {
        guard let data = try? JSONEncoder().encode(quickViewShortcut) else { return }
        defaults.set(data, forKey: Key.quickViewShortcut)
    }
}
