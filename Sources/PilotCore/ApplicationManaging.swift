import Foundation

@MainActor public protocol ApplicationManaging {
    func isInstalled(bundleID: String) -> Bool
    func isRunning(bundleID: String) -> Bool
    func open(bundleID: String) async throws
    func closeSafariWindow(id: Int) async throws
}
