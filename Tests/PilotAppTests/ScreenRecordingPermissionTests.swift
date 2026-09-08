import Testing
import Foundation
import PilotCore
import PilotOverview
@testable import PilotApp

@MainActor struct ScreenRecordingPermissionTests {
    @Test func startupAndRefreshOnlyCheckPermission() {
        var granted = false
        var requests = 0
        var settingsOpens = 0
        let permission = ScreenRecordingPermission(
            checkAccess: { granted },
            requestAccess: { requests += 1; return false },
            openSettings: { settingsOpens += 1; return true }
        )
        #expect(!permission.isGranted)
        granted = true
        permission.refresh()
        #expect(permission.isGranted)
        permission.enable()
        #expect(requests == 0 && settingsOpens == 0)
    }

    @Test func grantingFromRequestDoesNotOpenSettings() {
        var granted = false
        var settingsOpens = 0
        let permission = ScreenRecordingPermission(
            checkAccess: { granted },
            requestAccess: { granted = true; return true },
            openSettings: { settingsOpens += 1; return true }
        )
        permission.enable()
        #expect(permission.isGranted && permission.hasRequested)
        #expect(!permission.isRequesting && settingsOpens == 0)
    }

    @Test func unavailablePermissionRequestsOnceThenOffersSettings() {
        var granted = false
        var requests = 0
        var settingsOpens = 0
        let permission = ScreenRecordingPermission(
            checkAccess: { granted },
            requestAccess: { requests += 1; return false },
            openSettings: { settingsOpens += 1; return true }
        )
        permission.enable()
        permission.enable()
        #expect(!permission.isGranted)
        #expect(requests == 1 && settingsOpens == 2)
        granted = true
        permission.refresh()
        #expect(permission.isGranted)
        #expect(requests == 1 && settingsOpens == 2)
    }

    @Test func failedSettingsLaunchProvidesManualInstructions() {
        let permission = ScreenRecordingPermission(
            checkAccess: { false }, requestAccess: { false }, openSettings: { false }
        )
        permission.enable()
        #expect(permission.settingsError?.contains("Apple menu") == true)
        #expect(!permission.isGranted && !permission.isRequesting)
    }

    @Test func missingPermissionBlocksCaptureWithoutPromptingOrContactingAeroSpace() async {
        var requests = 0
        let permission = ScreenRecordingPermission(
            checkAccess: { false },
            requestAccess: { requests += 1; return false },
            openSettings: { Issue.record("Capture must not open Settings"); return false }
        )
        let model = PilotModel(screenRecordingPermission: permission)
        await model.capturePreviews()
        #expect(requests == 0 && !model.captureBusy)
        #expect(model.thumbnails.isEmpty && model.message == nil)
    }

    @Test func revocationClearsPreviewsEvenDuringAnUnrelatedOperation() async {
        var granted = true
        let permission = ScreenRecordingPermission(
            checkAccess: { granted }, requestAccess: { false }, openSettings: { false }
        )
        let model = PilotModel(screenRecordingPermission: permission)
        model.thumbnails = [Thumbnail(windowID: 1, state: .fresh, png: Data([1]), capturedAt: Date(), reason: nil)]
        model.previewWindowsByID = [1: DesktopWindow(id: 1, bundleID: "test.app", appName: "Test", title: "Test", workspace: "1")]
        model.captureDuration = 0.1
        model.busy = true
        granted = false
        await model.refreshHealth()
        #expect(!permission.isGranted)
        #expect(model.thumbnails.isEmpty && model.previewWindowsByID.isEmpty)
        #expect(model.captureDuration == nil)
    }
}
