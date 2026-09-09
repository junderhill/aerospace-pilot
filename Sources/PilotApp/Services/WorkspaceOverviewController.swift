import AppKit
import SwiftUI
import Observation
import PilotCore

@MainActor @Observable final class WorkspaceOverviewController {
    let model: WorkspaceOverviewModel
    let settings: PilotSettings
    private(set) var shortcutError: String?
    @ObservationIgnored private let shortcut = OverviewShortcut()
    @ObservationIgnored private let permission = ScreenRecordingPermission()
    @ObservationIgnored private var panel: OverviewPanel?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var navigationTask: Task<Void, Never>?
    @ObservationIgnored private var presentationID = UUID()

    init(settings: PilotSettings = PilotSettings()) {
        self.settings = settings
        self.model = WorkspaceOverviewModel()
    }

    var shortcutLabel: String { settings.quickViewShortcut.displayLabel }

    func start() {
        shortcutError = shortcut.start(configuration: settings.quickViewShortcut) { [weak self] in self?.toggle() }
    }

    func restartShortcut() {
        shortcutError = shortcut.restart(configuration: settings.quickViewShortcut)
    }

    func toggle() {
        if panel != nil { dismiss(); return }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        model.invalidate()
        let panel = OverviewPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Workspace Overview"
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.onDismiss = { [weak self] in self?.dismiss() }
        panel.contentView = NSHostingView(rootView: WorkspaceOverviewView(controller: self))
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        refresh()
    }

    func refresh() {
        loadTask?.cancel()
        loadTask = Task { await model.load() }
    }

    func activate(workspace: String, window: DesktopWindow? = nil) {
        guard navigationTask == nil else { return }
        let presentation = presentationID
        navigationTask = Task {
            let success = await model.activate(workspace: workspace, window: window)
            guard presentation == presentationID else { return }
            navigationTask = nil
            if success { dismiss() }
        }
    }

    func enablePreviews() {
        dismiss()
        permission.enable()
    }

    func dismiss() {
        presentationID = UUID()
        loadTask?.cancel(); loadTask = nil
        navigationTask?.cancel(); navigationTask = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        model.invalidate()
    }

    func stop() { dismiss(); shortcut.stop() }
}

private final class OverviewPanel: NSPanel {
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}
