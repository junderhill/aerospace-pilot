import Testing
import PilotCore
import PilotProfiles
@testable import PilotApp

@MainActor struct PilotModelTests {
    @Test func exportRemainsAvailableWithoutAnAeroSpaceConnection() throws {
        let model = PilotModel()
        let work = try Profile.work()
        model.profiles = [work]
        model.selectedProfileID = work.id
        #expect(model.health == nil)
        #expect(model.canExport)
        model.busy = true
        #expect(!model.canExport)
    }

    @Test func cancellingSafariDialogPreservesPreviewAndStartsNoRestore() throws {
        let model = PilotModel()
        let work = try Profile.work()
        let safari = DesktopWindow(id: 101, bundleID: Protection.safari, appName: "Safari", title: "Existing tabs", workspace: "other")
        model.profiles = [work]
        model.selectedProfileID = work.id
        model.plan = try RestorePlanner().plan(work, snapshot: DesktopSnapshot(windows: [safari]))

        model.beginApply()
        #expect(model.showingSafariDecision)
        #expect(!model.busy && !model.isRestoring)

        model.cancelSafariDecision()
        #expect(!model.showingSafariDecision)
        #expect(model.safariChoice == nil)
        #expect(!model.busy && !model.isRestoring)
        #expect(model.plan?.profile == work)
        #expect(model.report == nil)
    }
}
