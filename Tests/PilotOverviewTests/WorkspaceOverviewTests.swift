import Testing
import PilotCore
import PilotOverview

struct WorkspaceOverviewTests {
    @Test func groupsAllWorkspacesNaturallyIncludingEmptyAndOtherDisplays() {
        let snapshot = DesktopSnapshot(windows: [
            DesktopWindow(id: 1, bundleID: "test.editor", appName: "Editor", title: "Notes", workspace: "10", monitorID: 2),
            DesktopWindow(id: 2, bundleID: "test.browser", appName: "Browser", title: "Research", workspace: "B"),
            DesktopWindow(id: 3, bundleID: Protection.pilot, appName: "Pilot", title: "Overview", workspace: "2")
        ], workspaces: [Workspace(name: "10", monitorID: 2), Workspace(name: "2", isVisible: true), Workspace(name: "1")],
           monitors: [Monitor(id: 1, name: "Main"), Monitor(id: 2, name: "External")])
        let groups = OverviewWorkspace.groups(in: snapshot)
        #expect(groups.map(\.name) == ["1", "2", "10", "B"])
        #expect(groups[0].windows.isEmpty)
        #expect(groups[1].isVisible && groups[1].windows.isEmpty)
        #expect(groups[2].monitorName == "External")
        #expect(groups[2].monitorID == 2)
        #expect(groups[3].windows.map(\.id) == [2])
    }

    @Test func searchesWorkspaceAppAndTitleWithoutLosingWorkspaceIdentity() {
        let snapshot = DesktopSnapshot(windows: [
            DesktopWindow(id: 1, bundleID: "test.editor", appName: "Editor", title: "Roadmap", workspace: "Work"),
            DesktopWindow(id: 2, bundleID: "test.browser", appName: "Browser", title: "Reference", workspace: "Work")
        ], workspaces: [Workspace(name: "Work"), Workspace(name: "Empty")])
        #expect(OverviewWorkspace.groups(in: snapshot, matching: " work ").first?.windows.count == 2)
        #expect(OverviewWorkspace.groups(in: snapshot, matching: "EDITOR").first?.windows.map(\.id) == [1])
        #expect(OverviewWorkspace.groups(in: snapshot, matching: "reference").first?.name == "Work")
        #expect(OverviewWorkspace.groups(in: snapshot, matching: "empty").first?.windows.isEmpty == true)
        #expect(OverviewWorkspace.groups(in: snapshot, matching: "missing").isEmpty)
    }

    @Test func canHideEmptyAndPilotOnlyWorkspaces() {
        let snapshot = DesktopSnapshot(windows: [
            DesktopWindow(id: 1, bundleID: "test.editor", appName: "Editor", title: "Roadmap", workspace: "Work"),
            DesktopWindow(id: 2, bundleID: Protection.pilot, appName: "Pilot", title: "Quick View", workspace: "PilotOnly")
        ], workspaces: [Workspace(name: "Work"), Workspace(name: "Empty"), Workspace(name: "PilotOnly")])

        let groups = OverviewWorkspace.groups(in: snapshot, includingEmpty: false)
        #expect(groups.map(\.name) == ["Work"])
    }
}
