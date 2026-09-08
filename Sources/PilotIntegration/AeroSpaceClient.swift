import Foundation
import PilotCore

public struct AeroSpaceClient: DesktopClient {
    public let executable: URL
    public let runner: any ProcessRunning
    public let timeout: TimeInterval
    public init(executable: URL = Self.resolveExecutable(), runner: any ProcessRunning = ProcessRunner(), timeout: TimeInterval = 5) {
        self.executable = executable; self.runner = runner; self.timeout = timeout
    }
    public static func resolveExecutable(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["PILOT_AEROSPACE_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let candidates = ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace", "/Applications/AeroSpace.app/Contents/MacOS/aerospace"]
            + (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/aerospace" }
        return URL(fileURLWithPath: candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0])
    }
    @discardableResult public func command(_ arguments: [String]) async throws -> String {
        let result = try await runner.run(executable: executable, arguments: arguments, timeout: timeout)
        guard result.status == 0 else {
            throw CommandFailure(.exit, executable: executable.path, arguments: arguments,
                                 detail: result.stderr.isEmpty ? result.stdout : result.stderr, status: result.status)
        }
        return result.stdout
    }
    private func query<T: Decodable>(_ type: T.Type, _ arguments: [String]) async throws -> T {
        let output = try await command(arguments)
        do { return try JSONDecoder().decode(type, from: Data(output.utf8)) }
        catch {
            throw CommandFailure(.malformedResponse, executable: executable.path, arguments: arguments,
                                 detail: "Unsupported JSON response: \(error)")
        }
    }
    public func snapshot() async throws -> DesktopSnapshot {
        async let windows = query([DesktopWindow].self, ["list-windows", "--all", "--json", "--format", "%{window-id}%{app-bundle-id}%{app-name}%{window-title}%{workspace}%{monitor-id}"])
        async let workspaces = query([Workspace].self, ["list-workspaces", "--all", "--json", "--format", "%{workspace}%{monitor-id}%{workspace-is-visible}"])
        async let monitors = query([Monitor].self, ["list-monitors", "--json"])
        let snapshot = try await DesktopSnapshot(windows: windows, workspaces: workspaces, monitors: monitors)
        guard Set(snapshot.windows.map(\.id)).count == snapshot.windows.count,
              snapshot.windows.allSatisfy({ $0.id > 0 && !$0.bundleID.isEmpty && !$0.workspace.isEmpty }),
              Set(snapshot.workspaces.map(\.name)).count == snapshot.workspaces.count,
              !snapshot.monitors.isEmpty,
              Set(snapshot.monitors.map(\.id)).count == snapshot.monitors.count,
              snapshot.monitors.allSatisfy({ $0.id > 0 && !$0.name.isEmpty }) else {
            throw CommandFailure(.malformedResponse, executable: executable.path, arguments: ["snapshot"], detail: "Duplicate or invalid desktop identities.")
        }
        return snapshot
    }
    public func versions() async throws -> VersionPair { try VersionPair(output: await command(["--version"])) }
    public func move(windowID: Int, to workspace: String) async throws {
        guard windowID > 0, !workspace.isEmpty, !workspace.contains("\n") else { throw PilotError.invalid("Invalid window or workspace.") }
        // Protection also holds at the command boundary, independently of the planner.
        let current = try await snapshot()
        guard let window = current.windows.first(where: { $0.id == windowID }) else { throw PilotError.stale("Window \(windowID) disappeared.") }
        try Protection.requireMutable(window.bundleID)
        try await command(["move-node-to-workspace", "--window-id", String(windowID), "--", workspace])
    }
    public func focus(windowID: Int) async throws {
        guard windowID > 0 else { throw PilotError.invalid("Invalid window ID.") }
        try await command(["focus", "--window-id", String(windowID)])
    }
    public func close(windowID: Int, expectedBundleID: String) async throws {
        try Protection.requireMutable(expectedBundleID)
        let snapshot = try await snapshot()
        guard let window = snapshot.windows.first(where: { $0.id == windowID }), window.bundleID == expectedBundleID else {
            throw PilotError.stale("Window changed before close; preview again.")
        }
        try Protection.requireMutable(window.bundleID)
        // Normal AX close; no quit, force-quit, save-dialog dismissal or AppleScript tab manipulation.
        try await command(["close", "--window-id", String(windowID)])
    }
}
