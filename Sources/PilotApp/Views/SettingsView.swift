import AppKit
import SwiftUI
import PilotCore

struct SettingsView: View {
    @Bindable var settings: PilotSettings
    let model: PilotModel
    let overview: WorkspaceOverviewController
    @State private var customBundleID = ""
    @State private var validationMessage: String?

    var body: some View {
        Form {
            Section("Quick View") {
                LabeledContent("Keyboard shortcut") {
                    ShortcutRecorderView(shortcut: $settings.quickViewShortcut)
                        .frame(width: 150, height: 30)
                }
                Text("Click the shortcut field, then press the modifiers and key you want to use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Excluded applications") {
                Text("Excluded apps are ignored when saving a layout and stay unchanged during restore. Nothing is excluded by default.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ForEach(appChoices) { choice in
                    Toggle(isOn: binding(for: choice.bundleID)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(choice.name)
                            Text(choice.bundleID)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .disabled(Protection.immutable.contains(choice.bundleID))
                }

                HStack {
                    TextField("Bundle identifier", text: $customBundleID)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        addCustomBundleID()
                    }
                    .disabled(customBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 420)
        .navigationTitle("AeroSpace Pilot Settings")
        .onChange(of: settings.quickViewShortcut) { _, _ in
            overview.restartShortcut()
        }
    }

    private var appChoices: [AppChoice] {
        var names: [String: String] = [:]
        for window in model.health?.snapshot?.windows ?? [] {
            names[window.bundleID] = window.appName
        }
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, let bundleID = app.bundleIdentifier else { continue }
            names[bundleID] = app.localizedName ?? bundleID
        }
        for bundleID in settings.excludedBundleIDs where names[bundleID] == nil {
            names[bundleID] = bundleID
        }
        return names.map { AppChoice(bundleID: $0.key, name: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func binding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { settings.excludedBundleIDs.contains(bundleID) },
            set: { settings.setExcluded(bundleID, enabled: $0) }
        )
    }

    private func addCustomBundleID() {
        let raw = customBundleID
        guard settings.addExcluded(raw) else {
            validationMessage = "Enter a bundle identifier such as com.example.App."
            return
        }
        customBundleID = ""
        validationMessage = nil
    }

    private struct AppChoice: Identifiable {
        let bundleID: String
        let name: String
        var id: String { bundleID }
    }
}
