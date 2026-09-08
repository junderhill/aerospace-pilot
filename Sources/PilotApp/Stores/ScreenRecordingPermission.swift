import AppKit
import CoreGraphics
import Observation

/// The app owns consent; diagnostics and capture services never request it.
@MainActor @Observable final class ScreenRecordingPermission {
    private(set) var isGranted: Bool
    private(set) var hasRequested = false
    private(set) var isRequesting = false
    private(set) var settingsError: String?

    @ObservationIgnored private let checkAccess: () -> Bool
    @ObservationIgnored private let requestAccess: () -> Bool
    @ObservationIgnored private let openSettings: () -> Bool

    init(
        checkAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        requestAccess: @escaping () -> Bool = { CGRequestScreenCaptureAccess() },
        openSettings: @escaping () -> Bool = {
            let pane: String
            if #available(macOS 26, *) {
                pane = "com.apple.settings.PrivacySecurity.extension"
            } else {
                pane = "com.apple.preference.security"
            }
            guard let url = URL(string: "x-apple.systempreferences:\(pane)?Privacy_ScreenCapture") else { return false }
            return NSWorkspace.shared.open(url)
        }
    ) {
        self.checkAccess = checkAccess
        self.requestAccess = requestAccess
        self.openSettings = openSettings
        isGranted = checkAccess()
    }

    func refresh() {
        isGranted = checkAccess()
        if isGranted { settingsError = nil }
    }

    func showAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func enable() {
        guard !isRequesting else { return }
        refresh()
        guard !isGranted else { return }
        isRequesting = true
        defer { isRequesting = false }
        settingsError = nil
        if !hasRequested {
            hasRequested = true
            _ = requestAccess()
            refresh()
        }
        if !isGranted && !openSettings() {
            settingsError = "Could not open System Settings. Open it from the Apple menu, then choose Privacy & Security → Screen Recording."
        }
    }
}
