import SwiftUI
import AppKit
import PilotCore

@main struct AeroSpacePilotApp: App {
    @NSApplicationDelegateAdaptor(PilotAppDelegate.self) private var delegate
    @State private var settings: PilotSettings
    @State private var model: PilotModel
    @State private var overview: WorkspaceOverviewController

    init() {
        let settings = PilotSettings()
        _settings = State(initialValue: settings)
        _model = State(initialValue: PilotModel(settings: settings))
        _overview = State(initialValue: WorkspaceOverviewController(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model, overview: overview)
        } label: {
            MenuBarStatusItem(model: model, overview: overview)
        }
        .menuBarExtraStyle(.menu)

        Window("AeroSpace Pilot", id: "main") {
            ContentView(model: model, overview: overview)
                .frame(minWidth: 720, minHeight: 540)
        }
        .defaultSize(width: 900, height: 680)
        Settings {
            SettingsView(settings: settings, model: model, overview: overview)
        }
        .commands {
            CommandMenu("Navigate") {
                Button("Workspace Overview") { overview.toggle() }
            }
            CommandGroup(after: .newItem) {
                Button("Import Profile…") { model.importProfile() }.keyboardShortcut("o")
                    .disabled(model.busy)
                Button("Export Profile…") { model.exportProfile() }.keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!model.canExport)
            }
        }
    }
}

private struct MenuBarStatusItem: View {
    let model: PilotModel
    let overview: WorkspaceOverviewController

    var body: some View {
        Image(systemName: "rectangle.3.group")
            .accessibilityLabel("AeroSpace Pilot")
            .task {
                overview.start()
                await model.refresh()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    await model.refreshHealth()
                }
            }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                Task { await model.refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { await model.refreshHealth() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                overview.dismiss()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                overview.stop()
            }
    }
}

private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    let model: PilotModel
    let overview: WorkspaceOverviewController

    var body: some View {
        Button("Open AeroSpace Pilot", systemImage: "rectangle.3.group") {
            openWindow(id: "main")
        }

        Button("Workspace Overview", systemImage: "square.grid.2x2") {
            overview.toggle()
        }

        if model.busy {
            Divider()
            Label(model.isRestoring ? "Restoring layout…" : "Preparing layout…", systemImage: "arrow.triangle.2.circlepath")
        }

        Divider()
        SettingsLink {
            Label("Settings…", systemImage: "gear")
        }
        Divider()
        Button("Quit AeroSpace Pilot") {
            NSApplication.shared.terminate(nil)
        }
    }
}

@MainActor final class PilotAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            for window in NSApp.windows where window.title == "AeroSpace Pilot" {
                window.close()
            }
        }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--ready-file"), arguments.indices.contains(index + 1) {
            let payload = ["bundleID": Bundle.main.bundleIdentifier ?? "missing", "pid": String(ProcessInfo.processInfo.processIdentifier)]
            do { try JSONFiles.write(payload, to: URL(fileURLWithPath: arguments[index + 1])) }
            catch { fputs("Readiness write failed: \(error)\n", stderr) }
        }
    }
}
