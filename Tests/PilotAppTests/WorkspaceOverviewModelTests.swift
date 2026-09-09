import Foundation
import Testing
import PilotCore
import PilotOverview
@testable import PilotApp

@MainActor struct WorkspaceOverviewModelTests {
    private func desktop() -> DesktopSnapshot {
        DesktopSnapshot(windows: [DesktopWindow(id: 1, bundleID: "test.editor", appName: "Editor", title: "Document", workspace: "2")],
                        workspaces: [Workspace(name: "1"), Workspace(name: "2", isVisible: true)])
    }

    @Test func permissionDenialStillAllowsWorkspaceNavigation() async {
        let snapshot = desktop()
        var selected: String?
        let model = WorkspaceOverviewModel(readDesktop: { snapshot }, captureWindows: { _, _ in Issue.record("Must not capture") },
                                           hasPermission: { false }, switchWorkspace: { selected = $0 })
        await model.load()
        #expect(model.groups.count == 2 && !model.canCapture)
        #expect(model.selectedWorkspace == "2")
        model.moveSelection(1)
        #expect(model.selectedWorkspace == "1")
        #expect(await model.activate(workspace: "1"))
        #expect(selected == "1")
    }

    @Test func staleWindowCannotFocusAReusedIdentifier() async {
        let snapshot = desktop()
        var current = snapshot
        var focused: Int?
        let model = WorkspaceOverviewModel(readDesktop: { current }, hasPermission: { false }, focusWindow: { focused = $0 })
        await model.load()
        current.windows[0].bundleID = "different.app"
        #expect(await !model.activate(workspace: "2", window: snapshot.windows[0]))
        #expect(focused == nil && model.error != nil)
        current = snapshot
        #expect(await model.activate(workspace: "2", window: snapshot.windows[0]))
        #expect(focused == 1)
    }

    @Test func missingWorkspaceDoesNotCreateOne() async {
        let snapshot = desktop()
        let model = WorkspaceOverviewModel(readDesktop: { snapshot }, hasPermission: { false },
                                           switchWorkspace: { _ in Issue.record("Must not switch") })
        #expect(await !model.activate(workspace: "missing"))
        #expect(model.error != nil)
    }

    @Test func dismissedOverviewIgnoresLateThumbnailCallbacks() async {
        let snapshot = desktop()
        var lateUpdate: (@MainActor (Thumbnail) -> Void)?
        let thumbnail = Thumbnail(windowID: 1, state: .fresh, png: Data([1]), capturedAt: Date(), reason: nil)
        let model = WorkspaceOverviewModel(readDesktop: { snapshot }, captureWindows: { _, update in
            update(thumbnail)
            lateUpdate = update
        }, hasPermission: { true })
        await model.load()
        #expect(model.thumbnails.count == 1)
        model.invalidate()
        lateUpdate?(thumbnail)
        #expect(model.snapshot == nil && model.thumbnails.isEmpty)
        #expect(!model.loading && !model.capturing)
    }

    @Test func revokedPermissionClearsProgressiveImages() async {
        let snapshot = desktop()
        var granted = true
        var update: (@MainActor (Thumbnail) -> Void)?
        let thumbnail = Thumbnail(windowID: 1, state: .fresh, png: Data([1]), capturedAt: Date(), reason: nil)
        let model = WorkspaceOverviewModel(readDesktop: { snapshot }, captureWindows: { _, emit in
            emit(thumbnail); update = emit
        }, hasPermission: { granted })
        await model.load()
        #expect(model.thumbnails.count == 1)
        granted = false
        update?(thumbnail)
        #expect(!model.canCapture && model.thumbnails.isEmpty)
    }

    @Test func desktopFailureLeavesAnActionableError() async {
        let model = WorkspaceOverviewModel(readDesktop: { throw PilotError.unavailable("AeroSpace is offline") }, hasPermission: { false })
        await model.load()
        #expect(model.error == "AeroSpace is offline")
        #expect(!model.loading && model.groups.isEmpty)
    }

    @Test func quickViewPreferencesPersistAndSectionsFollowMonitorOrder() async {
        let suiteName = "WorkspaceOverviewModelTests-\(UUID().uuidString)"
        guard let preferences = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated preferences")
            return
        }
        defer { preferences.removePersistentDomain(forName: suiteName) }

        let snapshot = DesktopSnapshot(
            windows: [
                DesktopWindow(id: 1, bundleID: "test.editor", appName: "Editor", title: "Roadmap", workspace: "A", monitorID: 2),
                DesktopWindow(id: 2, bundleID: "test.browser", appName: "Browser", title: "Reference", workspace: "B", monitorID: 1)
            ],
            workspaces: [
                Workspace(name: "A", monitorID: 2),
                Workspace(name: "B", monitorID: 1),
                Workspace(name: "Empty", monitorID: 1)
            ],
            monitors: [Monitor(id: 1, name: "Built-in"), Monitor(id: 2, name: "External")]
        )
        let model = WorkspaceOverviewModel(readDesktop: { snapshot }, hasPermission: { false }, preferences: preferences)
        await model.load()

        #expect(model.groupByMonitor)
        #expect(!model.hideEmptyWorkspaces)
        #expect(model.hasMultipleMonitors)
        #expect(model.monitorSections.map(\.name) == ["Built-in", "External"])
        #expect(model.monitorSections[0].workspaces.map(\.name) == ["B", "Empty"])
        #expect(model.monitorSections[1].workspaces.map(\.name) == ["A"])

        model.hideEmptyWorkspaces = true
        #expect(model.groups.map(\.name) == ["A", "B"])
        #expect(model.monitorSections[0].workspaces.map(\.name) == ["B"])
        model.groupByMonitor = false
        #expect(!model.usesMonitorGrouping && model.monitorSections.isEmpty)

        let reloaded = WorkspaceOverviewModel(readDesktop: { snapshot }, hasPermission: { false }, preferences: preferences)
        #expect(!reloaded.groupByMonitor)
        #expect(reloaded.hideEmptyWorkspaces)
    }
}
