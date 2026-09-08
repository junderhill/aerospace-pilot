import SwiftUI
import AppKit
import PilotCore

@main struct AeroSpacePilotApp: App {
    @NSApplicationDelegateAdaptor(PilotAppDelegate.self) private var delegate
    @State private var model = PilotModel()
    var body: some Scene {
        WindowGroup("AeroSpace Pilot", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 720, minHeight: 540)
                .task {
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
        }
        .defaultSize(width: 900, height: 680)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Profile…") { model.importProfile() }.keyboardShortcut("o")
                    .disabled(model.busy)
                Button("Export Profile…") { model.exportProfile() }.keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!model.canExport)
            }
        }
    }
}

@MainActor final class PilotAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--ready-file"), arguments.indices.contains(index + 1) {
            let payload = ["bundleID": Bundle.main.bundleIdentifier ?? "missing", "pid": String(ProcessInfo.processInfo.processIdentifier)]
            do { try JSONFiles.write(payload, to: URL(fileURLWithPath: arguments[index + 1])) }
            catch { fputs("Readiness write failed: \(error)\n", stderr) }
        }
    }
}
