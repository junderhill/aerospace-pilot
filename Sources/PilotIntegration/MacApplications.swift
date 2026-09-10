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
    public func runningApplications() -> [RunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { application in
                guard let bundleID = application.bundleIdentifier, !bundleID.isEmpty else { return nil }
                return RunningApplication(
                    processID: application.processIdentifier,
                    bundleID: bundleID,
                    appName: application.localizedName ?? bundleID,
                    launchDate: application.launchDate
                )
            }
            .sorted { $0.processID < $1.processID }
    }
    public func open(bundleID: String) async throws {
        try Protection.requireMutable(bundleID, additional: client.globalProtections)
        guard isInstalled(bundleID: bundleID) else { throw PilotError.unavailable("Install \(bundleID) before restoring.") }
        // Launch Services reopens a running app with no window, without requesting a new instance.
        let result = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-g", "-b", bundleID], timeout: 10)
        guard result.status == 0 else { throw PilotError.unavailable("Could not open \(bundleID): \(result.stderr)") }
    }
    public func terminate(_ application: RunningApplication) async throws {
        try Protection.requireMutable(application.bundleID, additional: client.globalProtections)
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: application.bundleID)
            .first(where: { $0.processIdentifier == application.processID }) else {
            throw PilotError.stale("\(application.appName) is no longer running; cleanup skipped for that process.")
        }
        let observed = RunningApplication(
            processID: running.processIdentifier,
            bundleID: running.bundleIdentifier ?? application.bundleID,
            appName: running.localizedName ?? application.appName,
            launchDate: running.launchDate
        )
        guard application.matches(observed) else {
            throw PilotError.stale("\(application.appName) was relaunched before cleanup; the replacement was left running.")
        }
        // This is the normal termination request. It deliberately does not use
        // forceTerminate(), AppleScript, or save-dialog automation.
        guard running.terminate() else {
            throw PilotError.unavailable("\(application.appName) refused the normal quit request.")
        }
    }
    public func closeSafariWindow(id: Int) async throws {
        try await client.close(windowID: id, expectedBundleID: Protection.safari)
    }
}
