import Foundation

@MainActor public protocol ApplicationManaging {
    func isInstalled(bundleID: String) -> Bool
    func isRunning(bundleID: String) -> Bool
    /// Returns the regular applications visible to the user at this instant.
    /// The result is used both for previewing cleanup and for stale-target checks.
    func runningApplications() -> [RunningApplication]
    func open(bundleID: String) async throws
    /// Requests a normal application termination for the exact observed process.
    /// Implementations must not force-quit, dismiss save dialogs, or manipulate
    /// application content on the user's behalf.
    func terminate(_ application: RunningApplication) async throws
    func closeSafariWindow(id: Int) async throws
}
