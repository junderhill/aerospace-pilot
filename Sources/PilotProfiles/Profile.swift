import Foundation
import PilotCore

public struct WindowIdentity: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case exactTitle }
    public var kind: Kind
    public var value: String
    public init(exactTitle: String) { kind = .exactTitle; value = exactTitle }
    public func matches(_ window: DesktopWindow) -> Bool { window.title == value }
}

public struct SafariRecipe: Codable, Equatable, Sendable {
    public var logicalWindow: String
    public var urls: [String]
    public init(logicalWindow: String, urls: [String]) { self.logicalWindow = logicalWindow; self.urls = urls }
}

public struct Assignment: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var bundleID: String
    public var appName: String
    public var workspace: String
    public var identity: WindowIdentity?
    public var safariRecipe: SafariRecipe?
    public var preferredMonitorName: String?
    public init(id: String = UUID().uuidString, bundleID: String, appName: String, workspace: String,
                identity: WindowIdentity? = nil, safariRecipe: SafariRecipe? = nil, preferredMonitorName: String? = nil) {
        self.id = id; self.bundleID = bundleID; self.appName = appName; self.workspace = workspace
        self.identity = identity; self.safariRecipe = safariRecipe; self.preferredMonitorName = preferredMonitorName
    }
}

public struct CleanupSettings: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable { case keep, preview, automatic }
    public enum Scope: String, Codable, Sendable { case managedApplications, selectedWorkspaces, entireDesktop }
    public var mode: Mode
    public var scope: Scope
    public init(mode: Mode = .keep, scope: Scope = .managedApplications) { self.mode = mode; self.scope = scope }
}

public struct Profile: Codable, Equatable, Sendable, Identifiable {
    public enum MonitorPolicy: String, Codable, Sendable { case followAeroSpace }
    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var assignments: [Assignment]
    public var protectedBundleIDs: [String]
    public var cleanup: CleanupSettings
    public var monitorPolicy: MonitorPolicy
    public init(id: UUID = UUID(), name: String, assignments: [Assignment],
                protectedBundleIDs: [String] = Protection.required.sorted(), cleanup: CleanupSettings = .init()) {
        schemaVersion = 1; self.id = id; self.name = name; self.assignments = assignments
        self.protectedBundleIDs = protectedBundleIDs; self.cleanup = cleanup; monitorPolicy = .followAeroSpace
    }
    public func validate(globalProtections: Set<String> = []) throws {
        guard schemaVersion == 1 else { throw PilotError.invalid("Unsupported profile schema \(schemaVersion); supported schema is 1.") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200, !assignments.isEmpty else {
            throw PilotError.invalid("A profile needs a name (1–200 characters) and at least one assignment.")
        }
        guard Protection.required.isSubset(of: Set(protectedBundleIDs)) else {
            throw PilotError.invalid("Profile must carry all required ChatGPT protections.")
        }
        guard Set(assignments.map(\.id)).count == assignments.count else { throw PilotError.invalid("Assignment identifiers must be unique.") }
        for assignment in assignments {
            guard !assignment.id.isEmpty, assignment.bundleID.contains("."), !assignment.bundleID.contains(where: \.isWhitespace),
                  !assignment.appName.isEmpty, !assignment.workspace.isEmpty, assignment.workspace.count <= 100,
                  !assignment.workspace.contains(where: { $0.isNewline || $0.asciiValue == 0 }) else {
                throw PilotError.invalid("Invalid app identity or workspace in assignment \(assignment.id).")
            }
            try Protection.requireMutable(assignment.bundleID, additional: Set(protectedBundleIDs).union(globalProtections))
            if let identity = assignment.identity, identity.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw PilotError.invalid("Exact-title identity cannot be empty.")
            }
            if let recipe = assignment.safariRecipe {
                guard assignment.bundleID == Protection.safari, !recipe.logicalWindow.isEmpty, !recipe.urls.isEmpty else {
                    throw PilotError.invalid("A Safari recipe needs a logical window and at least one URL, assigned to Safari.")
                }
                guard recipe.urls.allSatisfy({ value in
                    guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                          let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return false }
                    return true
                }), Set(recipe.urls).count == recipe.urls.count else {
                    throw PilotError.invalid("Recipe URLs must be distinct HTTP(S) URLs without embedded credentials.")
                }
            }
        }
        for (bundleID, group) in Dictionary(grouping: assignments, by: \.bundleID) where group.count > 1 {
            guard bundleID != Protection.safari else { throw PilotError.invalid("Safari's all-window policy supports one destination per profile.") }
            guard group.allSatisfy({ $0.identity != nil }), Set(group.compactMap { $0.identity?.value }).count == group.count else {
                throw PilotError.invalid("Multiple assignments for \(bundleID) require distinct explicit window identities.")
            }
        }
    }
    public static func work() throws -> Profile {
        let resources = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("AeroSpacePilot_PilotProfiles.bundle")) } ?? Bundle.module
        guard let url = resources.url(forResource: "Work", withExtension: "json") else { throw PilotError.unavailable("Work seed is missing.") }
        return try ProfileStore.decode(Data(contentsOf: url))
    }
}
