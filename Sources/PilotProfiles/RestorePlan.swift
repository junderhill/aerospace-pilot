import Foundation
import PilotCore

public enum SafariChoice: String, Codable, CaseIterable, Sendable { case moveAll, leaveInPlace, closeAll, cancel }

/// Consent is scoped to the exact Safari window set seen in the preview.
public struct SafariConsent: Equatable, Sendable {
    public let choice: SafariChoice
    public let windows: [DesktopWindow]
    public init(choice: SafariChoice, snapshot: DesktopSnapshot) {
        self.choice = choice
        windows = snapshot.windows.filter { $0.bundleID == Protection.safari }.sorted { $0.id < $1.id }
    }
    public func matches(_ snapshot: DesktopSnapshot) -> Bool {
        windows == snapshot.windows.filter { $0.bundleID == Protection.safari }.sorted { $0.id < $1.id }
    }
}

public struct PlanItem: Equatable, Sendable, Identifiable {
    public enum Action: String, Sendable { case launch, move, alreadyPlaced, resolve, safariDecision, skipped, unsupported }
    public var id: String { assignment.id }
    public let assignment: Assignment
    public var action: Action
    public var windowIDs: [Int]
    public var detail: String
}

public struct RestorePlan: Sendable {
    public let profile: Profile
    public let snapshot: DesktopSnapshot
    public let items: [PlanItem]
    public let warnings: [String]
    /// Exact regular application processes observed while the preview was made.
    /// These identities are required before the apply step may request a normal
    /// quit, so a replacement process is never mistaken for the preview target.
    public let cleanupCandidates: [RunningApplication]
    /// Explicit workspace mappings plus safe legacy mappings inferred from
    /// assignment-level preferred monitor names.
    public let workspaceMonitorTargets: [SavedWorkspace]
    /// Retained for callers of the earlier cleanup preview API. This list only
    /// describes visible windows and does not include windowless applications.
    public let futureClosureCandidates: [DesktopWindow]
}

public struct RestorePlanner: Sendable {
    public let globalProtections: Set<String>
    public init(globalProtections: Set<String> = []) { self.globalProtections = globalProtections }
    public func plan(_ profile: Profile, snapshot: DesktopSnapshot,
                     runningApplications: [RunningApplication] = []) throws -> RestorePlan {
        try profile.validate(globalProtections: globalProtections)
        var warnings = ["Apps outside this profile stay open unless you select the cleanup option before applying."]
        var items: [PlanItem] = []
        for assignment in profile.assignments {
            if globalProtections.contains(assignment.bundleID) {
                items.append(PlanItem(assignment: assignment, action: .skipped, windowIDs: [],
                                      detail: "\(assignment.appName) is excluded in Settings and will stay unchanged."))
                continue
            }
            if let monitor = assignment.preferredMonitorName {
                let matches = snapshot.monitors.filter {
                    $0.name.localizedCaseInsensitiveCompare(monitor) == .orderedSame
                }
                if matches.isEmpty {
                    warnings.append("\(assignment.appName): display \(monitor) is absent. Use AeroSpace's current mapping for \(assignment.workspace).")
                } else if matches.count > 1 {
                    warnings.append("\(assignment.appName): display \(monitor) is ambiguous. Use AeroSpace's current mapping for \(assignment.workspace).")
                }
            }
            let windows = snapshot.windows.filter { $0.bundleID == assignment.bundleID }
            if assignment.safariRecipe != nil {
                items.append(PlanItem(assignment: assignment, action: .unsupported, windowIDs: [], detail: "Saved Safari tabs are not restored yet. Safari will stay unchanged."))
            } else if assignment.bundleID == Protection.safari && !windows.isEmpty {
                items.append(PlanItem(assignment: assignment, action: .safariDecision, windowIDs: windows.map(\.id), detail: "Choose how to handle all \(windows.count) existing Safari windows, including other workspaces."))
            } else {
                let matches = windows.filter { assignment.identity?.matches($0) ?? true }
                if matches.count == 1, let window = matches.first {
                    items.append(PlanItem(assignment: assignment, action: window.workspace == assignment.workspace ? .alreadyPlaced : .move,
                                          windowIDs: [window.id], detail: "\(window.title) → \(assignment.workspace)"))
                } else if windows.isEmpty {
                    items.append(PlanItem(assignment: assignment, action: .launch, windowIDs: [], detail: "Open \(assignment.appName), wait for its window, then place it in \(assignment.workspace)."))
                } else {
                    items.append(PlanItem(assignment: assignment, action: .resolve, windowIDs: matches.isEmpty ? windows.map(\.id) : matches.map(\.id),
                                          detail: matches.isEmpty ? "No exact identity match. Select a current window explicitly." : "Multiple matches. Select a current window explicitly."))
                }
            }
        }
        var workspaceMonitorTargets = profile.workspaces
        let explicitWorkspaceNames = Set(workspaceMonitorTargets.map(\.name))
        let inferredAssignments = Dictionary(grouping: profile.assignments, by: \.workspace)
        for workspaceName in inferredAssignments.keys.sorted() where !explicitWorkspaceNames.contains(workspaceName) {
            let monitorNames = Set(inferredAssignments[workspaceName, default: []].compactMap(\.preferredMonitorName))
            if monitorNames.count == 1, let monitorName = monitorNames.first {
                workspaceMonitorTargets.append(SavedWorkspace(name: workspaceName, preferredMonitorName: monitorName))
            } else if monitorNames.count > 1 {
                warnings.append("Workspace \(workspaceName): assignments disagree about its saved display; no workspace move will be attempted.")
            }
        }
        for workspace in workspaceMonitorTargets {
            guard let monitor = workspace.preferredMonitorName else { continue }
            let matches = snapshot.monitors.filter {
                $0.name.localizedCaseInsensitiveCompare(monitor) == .orderedSame
            }
            if matches.isEmpty {
                warnings.append("Workspace \(workspace.name): display \(monitor) is absent; it will keep AeroSpace's current mapping.")
            } else if matches.count > 1 {
                warnings.append("Workspace \(workspace.name): display \(monitor) is ambiguous; it will keep AeroSpace's current mapping.")
            }
        }
        let protected = Protection.immutable.union(profile.protectedBundleIDs).union(globalProtections)
        let managed = Set(profile.assignments.map(\.bundleID))
        let workspaces = Set(profile.assignments.map(\.workspace))
        let candidates = snapshot.windows.filter { window in
            guard !protected.contains(window.bundleID), !managed.contains(window.bundleID) else { return false }
            switch profile.cleanup.scope {
            case .managedApplications: return false
            case .selectedWorkspaces: return workspaces.contains(window.workspace)
            case .entireDesktop: return true
            }
        }
        let cleanupCandidates = runningApplications.filter { application in
            !protected.contains(application.bundleID) && !managed.contains(application.bundleID)
        }.sorted { lhs, rhs in
            lhs.appName.localizedStandardCompare(rhs.appName) == .orderedAscending
                || (lhs.appName == rhs.appName && lhs.processID < rhs.processID)
        }
        return RestorePlan(profile: profile, snapshot: snapshot, items: items, warnings: warnings,
                           cleanupCandidates: cleanupCandidates,
                           workspaceMonitorTargets: workspaceMonitorTargets,
                           futureClosureCandidates: candidates)
    }
}
