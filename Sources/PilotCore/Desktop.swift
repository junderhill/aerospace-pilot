import Foundation

public struct DesktopWindow: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var bundleID: String
    public var appName: String
    public var title: String
    public var workspace: String
    public var monitorID: Int
    public init(id: Int, bundleID: String, appName: String, title: String, workspace: String, monitorID: Int = 1) {
        self.id = id; self.bundleID = bundleID; self.appName = appName
        self.title = title; self.workspace = workspace; self.monitorID = monitorID
    }
    enum CodingKeys: String, CodingKey {
        case id = "window-id", bundleID = "app-bundle-id", appName = "app-name"
        case title = "window-title", workspace, monitorID = "monitor-id"
    }
}

public struct Workspace: Codable, Equatable, Sendable {
    public var name: String
    public var monitorID: Int
    public var isVisible: Bool
    public init(name: String, monitorID: Int = 1, isVisible: Bool = false) {
        self.name = name; self.monitorID = monitorID; self.isVisible = isVisible
    }
    enum CodingKeys: String, CodingKey {
        case name = "workspace", monitorID = "monitor-id", isVisible = "workspace-is-visible"
    }
}

public struct Monitor: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String
    public init(id: Int, name: String) { self.id = id; self.name = name }
    enum CodingKeys: String, CodingKey { case id = "monitor-id", name = "monitor-name" }
}

/// A running application's process identity as observed during a restore preview.
///
/// Bundle identifiers are not sufficient for destructive actions: an application
/// can be quit and relaunched between preview and apply.  The process identifier
/// is the primary identity and launch date, when macOS supplies it, provides an
/// additional guard against accidentally targeting the replacement process.
public struct RunningApplication: Codable, Equatable, Sendable, Identifiable {
    public var processID: Int32
    public var bundleID: String
    public var appName: String
    public var launchDate: Date?

    public var id: Int32 { processID }

    public init(processID: Int32, bundleID: String, appName: String, launchDate: Date? = nil) {
        self.processID = processID
        self.bundleID = bundleID
        self.appName = appName
        self.launchDate = launchDate
    }

    /// Returns true when the process is the same process observed at preview time.
    /// If either launch date is unavailable, the process ID remains the strongest
    /// identity macOS gives us and is used on its own.
    public func matches(_ other: Self) -> Bool {
        processID == other.processID &&
            bundleID == other.bundleID &&
            (launchDate == nil || other.launchDate == nil || launchDate == other.launchDate)
    }
}

public struct DesktopSnapshot: Codable, Equatable, Sendable {
    public var windows: [DesktopWindow]
    public var workspaces: [Workspace]
    public var monitors: [Monitor]
    public init(windows: [DesktopWindow], workspaces: [Workspace] = [], monitors: [Monitor] = []) {
        self.windows = windows; self.workspaces = workspaces; self.monitors = monitors
    }
}

public protocol DesktopClient: Sendable {
    func snapshot() async throws -> DesktopSnapshot
    func move(windowID: Int, to workspace: String) async throws
    func move(workspace: String, toMonitor monitorPattern: String) async throws
    func focus(windowID: Int) async throws
}

public enum PilotError: Error, LocalizedError, Equatable, Sendable {
    case invalid(String)
    case unavailable(String)
    case stale(String)
    public var errorDescription: String? {
        switch self { case .invalid(let s), .unavailable(let s), .stale(let s): s }
    }
}

public enum Protection {
    public static let pilot = "uk.jason.aerospace-pilot"
    /// The app itself is always excluded so it cannot manage its own windows.
    public static let immutable: Set<String> = [pilot]
    public static let safari = "com.apple.Safari"
    public static func requireMutable(_ bundleID: String, additional: Set<String> = []) throws {
        guard !immutable.union(additional).contains(bundleID) else {
            throw PilotError.invalid("\(bundleID) is protected; its running state, windows and content must remain unchanged.")
        }
    }
}
