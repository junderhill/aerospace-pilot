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
    public let futureClosureCandidates: [DesktopWindow]
}

public struct RestorePlanner: Sendable {
    public let globalProtections: Set<String>
    public init(globalProtections: Set<String> = []) { self.globalProtections = globalProtections }
    public func plan(_ profile: Profile, snapshot: DesktopSnapshot) throws -> RestorePlan {
        try profile.validate(globalProtections: globalProtections)
        var warnings = ["Apps outside this profile will stay open."]
        var items: [PlanItem] = []
        for assignment in profile.assignments {
            if globalProtections.contains(assignment.bundleID) {
                items.append(PlanItem(assignment: assignment, action: .skipped, windowIDs: [],
                                      detail: "\(assignment.appName) is excluded in Settings and will stay unchanged."))
                continue
            }
            if let monitor = assignment.preferredMonitorName, !snapshot.monitors.contains(where: { $0.name == monitor }) {
                warnings.append("\(assignment.appName): display \(monitor) is absent. Use AeroSpace's current mapping for \(assignment.workspace).")
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
        let protected = Protection.immutable.union(profile.protectedBundleIDs).union(globalProtections).union([Protection.safari])
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
        return RestorePlan(profile: profile, snapshot: snapshot, items: items, warnings: warnings, futureClosureCandidates: candidates)
    }
}
