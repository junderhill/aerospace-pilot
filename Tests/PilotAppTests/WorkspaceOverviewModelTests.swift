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
}
