import AppKit
import PilotCore

@MainActor public final class MacApplications: ApplicationManaging {
    private let client: AeroSpaceClient
    private let runner: any ProcessRunning
    public init(client: AeroSpaceClient, runner: any ProcessRunning = ProcessRunner()) {
        self.client = client; self.runner = runner
    }
    public func isInstalled(bundleID: String) -> Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }
    public func isRunning(bundleID: String) -> Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    public func open(bundleID: String) async throws {
        try Protection.requireMutable(bundleID)
        guard isInstalled(bundleID: bundleID) else { throw PilotError.unavailable("Install \(bundleID) before restoring.") }
        // Launch Services reopens a running app with no window, without requesting a new instance.
        let result = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-g", "-b", bundleID], timeout: 10)
        guard result.status == 0 else { throw PilotError.unavailable("Could not open \(bundleID): \(result.stderr)") }
    }
    public func closeSafariWindow(id: Int) async throws {
        try await client.close(windowID: id, expectedBundleID: Protection.safari)
    }
}
