import Foundation
import PilotCore
import PilotIntegration

public actor FakeProcessRunner: ProcessRunning {
    public enum Reply: Sendable { case result(CommandResult), failure(CommandFailure) }
    private var replies: [String: Reply]
    public private(set) var calls: [[String]] = []
    public init(replies: [String: Reply]) { self.replies = replies }
    public func set(_ command: String, reply: Reply) { replies[command] = reply }
    public func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        calls.append(arguments)
        guard let reply = replies[arguments.first ?? ""] else {
            throw PilotError.invalid("Unconfigured fake command: \(arguments)")
        }
        switch reply { case .result(let result): return result; case .failure(let error): throw error }
    }
    public static func healthy(version: String = "0.21.3-Beta hash") -> FakeProcessRunner {
        FakeProcessRunner(replies: [
            "--version": .result(.init(stdout: "aerospace CLI client version: \(version)\nAeroSpace.app server version: \(version)\n")),
            "list-windows": .result(.init(stdout: "[]")),
            "list-workspaces": .result(.init(stdout: "[{\"workspace\":\"1\",\"monitor-id\":1,\"workspace-is-visible\":true}]")),
            "list-monitors": .result(.init(stdout: "[{\"monitor-id\":1,\"monitor-name\":\"Test Display\"}]")),
        ])
    }
}

public actor MemoryDesktop: DesktopClient {
    public var state: DesktopSnapshot
    public private(set) var moves: [(Int, String)] = []
    public private(set) var focuses: [Int] = []
    private var pending: [(Int, DesktopWindow)] = []
    private var refusal = false
    private var disappearingIDs: Set<Int> = []
    public init(windows: [DesktopWindow] = []) {
        state = DesktopSnapshot(windows: windows, workspaces: [Workspace(name: "start", isVisible: true)], monitors: [Monitor(id: 1, name: "Test Display")])
    }
    public func replaceWindows(_ windows: [DesktopWindow]) { state.windows = windows }
    public func remove(_ id: Int) { state.windows.removeAll { $0.id == id } }
    public func refuseMoves() { refusal = true }
    public func disappearOnMove(_ id: Int) { disappearingIDs.insert(id) }
    public func schedule(_ window: DesktopWindow, afterSnapshots: Int = 0) { pending.append((afterSnapshots, window)) }
    public func snapshot() async throws -> DesktopSnapshot {
        var next: [(Int, DesktopWindow)] = []
        for (count, window) in pending {
            if count <= 0 { state.windows.append(window) } else { next.append((count - 1, window)) }
        }
        pending = next
        return state
    }
    public func move(windowID: Int, to workspace: String) async throws {
        moves.append((windowID, workspace))
        if disappearingIDs.contains(windowID) { state.windows.removeAll { $0.id == windowID }; return }
        guard !refusal else { return }
        if let index = state.windows.firstIndex(where: { $0.id == windowID }) { state.windows[index].workspace = workspace }
    }
    public func focus(windowID: Int) async throws { focuses.append(windowID) }
}

@MainActor public final class MemoryApplications: ApplicationManaging {
    public let desktop: MemoryDesktop
    public var installed: Set<String>
    public var running: Set<String> = []
    public var createdTitles: [String: String] = [:]
    public var launchFails: Set<String> = []
    public var createsWindows = true
    public var closeRefused = false
    public var delaySnapshots = 0
    public private(set) var opened: [String] = []
    public private(set) var closed: [Int] = []
    private var nextID = 1000
    public init(desktop: MemoryDesktop, installed: Set<String>) { self.desktop = desktop; self.installed = installed }
    public func isInstalled(bundleID: String) -> Bool { installed.contains(bundleID) }
    public func isRunning(bundleID: String) -> Bool { running.contains(bundleID) }
    public func open(bundleID: String) async throws {
        if launchFails.contains(bundleID) { throw PilotError.unavailable("Injected launch failure") }
        opened.append(bundleID); running.insert(bundleID)
        if createsWindows {
            nextID += 1
            await desktop.schedule(DesktopWindow(id: nextID, bundleID: bundleID, appName: bundleID,
                                                 title: createdTitles[bundleID] ?? "Window", workspace: "start"), afterSnapshots: delaySnapshots)
        }
    }
    public func closeSafariWindow(id: Int) async throws {
        closed.append(id)
        if !closeRefused { await desktop.remove(id) }
    }
}
