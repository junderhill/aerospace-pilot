import Foundation
import PilotCore

public struct RestoreOutcome: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable { case completed, skipped, cancelled, failed, unresolved }
    public var id: String { assignmentID }
    public let assignmentID: String
    public let appName: String
    public let workspace: String
    public let status: Status
    public let detail: String
    public let windowIDs: [Int]
}

public struct WorkspaceRestoreOutcome: Codable, Equatable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable { case completed, skipped, failed }
    public var id: String { workspace }
    public let workspace: String
    public let monitorName: String
    public let status: Status
    public let detail: String

    public init(workspace: String, monitorName: String, status: Status, detail: String) {
        self.workspace = workspace
        self.monitorName = monitorName
        self.status = status
        self.detail = detail
    }
}

public struct RestoreReport: Codable, Sendable {
    public let profileName: String
    public let outcomes: [RestoreOutcome]
    public let workspaceOutcomes: [WorkspaceRestoreOutcome]
    public let cleanup: String
    public var allPlacementsVerified: Bool {
        !outcomes.isEmpty &&
            outcomes.allSatisfy { $0.status == .completed } &&
            workspaceOutcomes.allSatisfy { $0.status != .failed }
    }
    public init(profileName: String, outcomes: [RestoreOutcome], cleanup: String,
                workspaceOutcomes: [WorkspaceRestoreOutcome] = []) {
        self.profileName = profileName
        self.outcomes = outcomes
        self.workspaceOutcomes = workspaceOutcomes
        self.cleanup = cleanup
    }
    public var summary: String {
        [RestoreOutcome.Status.completed, .skipped, .unresolved, .failed, .cancelled].map { status in
            "\(outcomes.filter { $0.status == status }.count) \(status.rawValue)"
        }.joined(separator: ", ")
    }
}

/// Explicit selections are tied to observed windows, never persisted in profile files.
public struct WindowResolution: Sendable {
    public let assignmentID: String
    public let window: DesktopWindow
    public init(assignmentID: String, window: DesktopWindow) { self.assignmentID = assignmentID; self.window = window }
}

@MainActor public final class RestoreEngine {
    private let desktop: any DesktopClient
    private let apps: any ApplicationManaging
    private let preflight: @Sendable () async throws -> Void
    private let globalProtections: Set<String>
    private let windowTimeout: TimeInterval
    private let pollInterval: Duration
    private var isApplying = false

    public init(desktop: any DesktopClient, apps: any ApplicationManaging, globalProtections: Set<String> = [],
                windowTimeout: TimeInterval = 15, pollInterval: Duration = .milliseconds(200),
                preflight: @escaping @Sendable () async throws -> Void) {
        self.desktop = desktop; self.apps = apps; self.globalProtections = globalProtections
        self.windowTimeout = windowTimeout; self.pollInterval = pollInterval; self.preflight = preflight
    }

    public func apply(_ preview: RestorePlan, safariConsent: SafariConsent? = nil,
                      resolutions: [WindowResolution] = [],
                      closeAppsOutsideLayout: Bool = false) async throws -> RestoreReport {
        guard !isApplying else { throw PilotError.unavailable("A restore is already running.") }
        try preview.profile.validate(globalProtections: globalProtections)
        isApplying = true
        defer { isApplying = false }
        try await preflight() // Recheck versions/capabilities immediately before every apply.
        let fresh = try await desktop.snapshot()
        let relevant = Set(preview.items.filter { $0.action != .skipped }.map { $0.assignment.bundleID })
        func relevantWindows(_ snapshot: DesktopSnapshot) -> [DesktopWindow] {
            snapshot.windows.filter { relevant.contains($0.bundleID) }.sorted { $0.id < $1.id }
        }
        guard relevantWindows(preview.snapshot) == relevantWindows(fresh), preview.snapshot.monitors == fresh.monitors,
              preview.snapshot.workspaces == fresh.workspaces else {
            throw PilotError.stale("Desktop changed since preview. Refresh the preview before applying; no changes made.")
        }
        guard Set(resolutions.map(\.assignmentID)).count == resolutions.count,
              Set(resolutions.map { $0.window.id }).count == resolutions.count else {
            throw PilotError.invalid("Each explicit resolution must select a distinct window and assignment.")
        }
        let protected = Protection.immutable.union(preview.profile.protectedBundleIDs).union(globalProtections)
        var outcomes: [RestoreOutcome] = []
        var consumed = Set<Int>()
        for item in preview.items {
            let assignment = item.assignment
            func outcome(_ status: RestoreOutcome.Status, _ detail: String, ids: [Int] = []) -> RestoreOutcome {
                RestoreOutcome(assignmentID: assignment.id, appName: assignment.appName, workspace: assignment.workspace,
                               status: status, detail: detail, windowIDs: ids)
            }
            if Task.isCancelled { outcomes.append(outcome(.cancelled, "Restore cancelled before this assignment.")); continue }
            if item.action == .skipped {
                outcomes.append(outcome(.skipped, item.detail))
                continue
            }
            do {
                try Protection.requireMutable(assignment.bundleID, additional: protected)
                if assignment.safariRecipe != nil {
                    outcomes.append(outcome(.unresolved, "Saved Safari tabs are not restored yet. Safari was left unchanged.")); continue
                }
                var current = try await desktop.snapshot()
                var windows = current.windows.filter { $0.bundleID == assignment.bundleID }
                if assignment.bundleID == Protection.safari && !windows.isEmpty {
                    guard let consent = safariConsent, consent.matches(current) else {
                        outcomes.append(outcome(.unresolved, "Safari needs a decision for its current full window set. Refresh preview.")); continue
                    }
                    switch consent.choice {
                    case .cancel:
                        outcomes.append(outcome(.cancelled, "Safari decision cancelled. No Safari changes.")); continue
                    case .leaveInPlace:
                        outcomes.append(outcome(.skipped, "All existing Safari windows/tabs left in place by choice.")); continue
                    case .moveAll:
                        var expected = windows
                        for window in windows {
                            let now = try await desktop.snapshot()
                            guard now.windows.filter({ $0.bundleID == Protection.safari }).sorted(by: { $0.id < $1.id }) == expected.sorted(by: { $0.id < $1.id }) else {
                                throw PilotError.stale("Safari windows changed during move-all. Further Safari work stopped; preview again.")
                            }
                            try await place(window, assignment: assignment, protected: protected)
                            let after = try await desktop.snapshot()
                            guard let updated = after.windows.first(where: { $0.id == window.id }) else { throw PilotError.stale("Safari window disappeared after placement.") }
                            expected = expected.map { $0.id == window.id ? updated : $0 }
                        }
                        try await verify(windows.map(\.id), assignment: assignment)
                        outcomes.append(outcome(.completed, "All approved Safari windows verified in \(assignment.workspace).", ids: windows.map(\.id)))
                        continue
                    case .closeAll:
                        var remaining = windows
                        for window in windows {
                            try Task.checkCancellation()
                            let now = try await desktop.snapshot()
                            guard now.windows.filter({ $0.bundleID == Protection.safari }).sorted(by: { $0.id < $1.id }) == remaining.sorted(by: { $0.id < $1.id }) else {
                                throw PilotError.stale("Safari changed during close-all. Further closing stopped; preview again.")
                            }
                            try Protection.requireMutable(assignment.bundleID, additional: protected)
                            try await apps.closeSafariWindow(id: window.id)
                            try await waitUntilClosed(window.id)
                            remaining.removeAll { $0.id == window.id }
                        }
                        current = try await desktop.snapshot()
                        windows = current.windows.filter { $0.bundleID == Protection.safari }
                        guard windows.isEmpty else { throw PilotError.stale("New Safari content appeared; stopped before opening or moving anything else.") }
                    }
                }
                if windows.isEmpty {
                    guard apps.isInstalled(bundleID: assignment.bundleID) else {
                        outcomes.append(outcome(.failed, "\(assignment.appName) is not installed (\(assignment.bundleID)).")); continue
                    }
                    try Task.checkCancellation()
                    try Protection.requireMutable(assignment.bundleID, additional: protected)
                    // A fresh read prevents a delayed user/app launch from being reopened unnecessarily.
                    windows = try await desktop.snapshot().windows.filter { $0.bundleID == assignment.bundleID }
                    if windows.isEmpty { try await apps.open(bundleID: assignment.bundleID) }
                    windows = try await waitForWindows(bundleID: assignment.bundleID)
                }
                let selection: DesktopWindow?
                if let resolution = resolutions.first(where: { $0.assignmentID == assignment.id }) {
                    guard resolution.window.bundleID == assignment.bundleID,
                          let live = windows.first(where: { $0 == resolution.window }) else {
                        outcomes.append(outcome(.unresolved, "Explicit window selection became stale; select again.")); continue
                    }
                    selection = live
                } else {
                    let matches = windows.filter { (assignment.identity?.matches($0) ?? true) && !consumed.contains($0.id) }
                    selection = matches.count == 1 ? matches[0] : nil
                }
                guard let selection, !consumed.contains(selection.id) else {
                    outcomes.append(outcome(.unresolved, "No unique window identity. Refresh preview and select a window explicitly.")); continue
                }
                try await place(selection, assignment: assignment, protected: protected)
                consumed.insert(selection.id)
                outcomes.append(outcome(.completed, "Placement verified in \(assignment.workspace).", ids: [selection.id]))
            } catch {
                outcomes.append(outcome(Task.isCancelled ? .cancelled : .failed, error.localizedDescription))
            }
        }
        // Workspace moves happen after window placement. Moving a workspace can
        // update the monitor ID reported for all of its windows, so doing this
        // last keeps window resolution and Safari consent scoped to their
        // original preview state.
        var workspaceOutcomes = [WorkspaceRestoreOutcome]()
        let safariCanMoveWorkspace: Bool = {
            guard let safariAssignment = preview.profile.assignments.first(where: { $0.bundleID == Protection.safari }),
                  safariAssignment.safariRecipe == nil,
                  let safariOutcome = outcomes.first(where: { $0.assignmentID == safariAssignment.id }),
                  safariOutcome.status == .completed else {
                return false
            }
            if !preview.snapshot.windows.contains(where: { $0.bundleID == Protection.safari }) {
                // A cold restore opened Safari as part of this apply; no
                // pre-existing Safari decision was needed.
                return true
            }
            return safariConsent?.choice == .moveAll || safariConsent?.choice == .closeAll
        }()
        let allowedSafariWindowIDs = Set(
            outcomes.first(where: {
                guard let safariAssignment = preview.profile.assignments.first(where: { $0.bundleID == Protection.safari }) else {
                    return false
                }
                return $0.assignmentID == safariAssignment.id
            })?.windowIDs ?? []
        )
        for savedWorkspace in preview.workspaceMonitorTargets.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            guard !Task.isCancelled else {
                workspaceOutcomes.append(.init(
                    workspace: savedWorkspace.name,
                    monitorName: savedWorkspace.preferredMonitorName ?? "unspecified",
                    status: .skipped,
                    detail: "Restore was cancelled before workspace monitor placement."
                ))
                break
            }
            guard let monitorName = savedWorkspace.preferredMonitorName else {
                workspaceOutcomes.append(.init(
                    workspace: savedWorkspace.name,
                    monitorName: "unspecified",
                    status: .skipped,
                    detail: "No saved display was recorded; AeroSpace's current mapping was kept."
                ))
                continue
            }
            do {
                let current = try await desktop.snapshot()
                guard let workspace = current.workspaces.first(where: { $0.name == savedWorkspace.name }) else {
                    workspaceOutcomes.append(.init(
                        workspace: savedWorkspace.name,
                        monitorName: monitorName,
                        status: .skipped,
                        detail: "Workspace is not present and has no windows to place; nothing was created."
                    ))
                    continue
                }
                let protectedBundles = Protection.immutable
                    .union(preview.profile.protectedBundleIDs)
                    .union(globalProtections)
                if current.windows.contains(where: {
                    $0.workspace == savedWorkspace.name && protectedBundles.contains($0.bundleID)
                }) {
                    workspaceOutcomes.append(.init(
                        workspace: savedWorkspace.name,
                        monitorName: monitorName,
                        status: .skipped,
                        detail: "A protected or excluded application is in this workspace; its display was left unchanged."
                    ))
                    continue
                }
                let safariWindows = current.windows.filter {
                    $0.workspace == savedWorkspace.name && $0.bundleID == Protection.safari
                }
                if !safariWindows.isEmpty,
                   (!safariCanMoveWorkspace || !safariWindows.allSatisfy({ allowedSafariWindowIDs.contains($0.id) })) {
                    workspaceOutcomes.append(.init(
                        workspace: savedWorkspace.name,
                        monitorName: monitorName,
                        status: .skipped,
                        detail: "Safari was not approved for movement; this workspace's display was left unchanged."
                    ))
                    continue
                }
                let matchingMonitors = current.monitors.filter {
                    $0.name.localizedCaseInsensitiveCompare(monitorName) == .orderedSame
                }
                guard matchingMonitors.count == 1, let target = matchingMonitors.first else {
                    let detail = matchingMonitors.isEmpty
                        ? "Display is absent; AeroSpace's current mapping was kept."
                        : "Display name is ambiguous; AeroSpace's current mapping was kept."
                    workspaceOutcomes.append(.init(
                        workspace: savedWorkspace.name,
                        monitorName: monitorName,
                        status: .skipped,
                        detail: detail
                    ))
                    continue
                }
                if workspace.monitorID == target.id {
                    workspaceOutcomes.append(.init(
                        workspace: savedWorkspace.name,
                        monitorName: monitorName,
                        status: .completed,
                        detail: "Already assigned to the saved display."
                    ))
                    continue
                }
                try Task.checkCancellation()
                try await desktop.move(workspace: savedWorkspace.name, toMonitor: monitorName)
                let after = try await desktop.snapshot()
                guard let placed = after.workspaces.first(where: { $0.name == savedWorkspace.name }),
                      placed.monitorID == target.id else {
                    throw PilotError.unavailable("Workspace \(savedWorkspace.name) did not reach display \(monitorName).")
                }
                workspaceOutcomes.append(.init(
                    workspace: savedWorkspace.name,
                    monitorName: monitorName,
                    status: .completed,
                    detail: "Assigned to the saved display."
                ))
            } catch is CancellationError {
                workspaceOutcomes.append(.init(
                    workspace: savedWorkspace.name,
                    monitorName: monitorName,
                    status: .skipped,
                    detail: "Restore was cancelled before workspace monitor placement."
                ))
                break
            } catch {
                workspaceOutcomes.append(.init(
                    workspace: savedWorkspace.name,
                    monitorName: monitorName,
                    status: .failed,
                    detail: error.localizedDescription
                ))
            }
        }

        // Earlier successful placements may change while another application is starting.
        for index in outcomes.indices where outcomes[index].status == .completed {
            let old = outcomes[index]
            guard let assignment = preview.profile.assignments.first(where: { $0.id == old.assignmentID }) else { continue }
            do { try await verify(old.windowIDs, assignment: assignment) }
            catch {
                outcomes[index] = RestoreOutcome(assignmentID: old.assignmentID, appName: old.appName, workspace: old.workspace,
                                                 status: .failed, detail: "Final verification: \(error.localizedDescription)", windowIDs: old.windowIDs)
            }
        }
        let cleanup = closeAppsOutsideLayout
            ? await closeOutsideApplications(preview: preview)
            : "Apps outside this profile were left open."
        return RestoreReport(
            profileName: preview.profile.name,
            outcomes: outcomes,
            cleanup: cleanup,
            workspaceOutcomes: workspaceOutcomes
        )
    }

    private func closeOutsideApplications(preview: RestorePlan) async -> String {
        let expected = preview.cleanupCandidates
        let protected = Protection.immutable.union(preview.profile.protectedBundleIDs).union(globalProtections)
        let managed = Set(preview.profile.assignments.map(\.bundleID))
        guard !expected.isEmpty else {
            return "No applications outside this layout were in the preview."
        }
        guard expected.allSatisfy({ !protected.contains($0.bundleID) && !managed.contains($0.bundleID) }) else {
            return "Cleanup was not applied: Settings or the saved layout now protects a previewed application."
        }

        let current = apps.runningApplications()
        let currentTargets = current.filter {
            !protected.contains($0.bundleID) && !managed.contains($0.bundleID)
        }
        let expectedByProcess = Dictionary(uniqueKeysWithValues: expected.map { ($0.processID, $0) })
        func hasCleanupDrift(_ applications: [RunningApplication]) -> Bool {
            applications.contains { application in
                guard !protected.contains(application.bundleID), !managed.contains(application.bundleID) else {
                    return false
                }
                guard let original = expectedByProcess[application.processID] else { return true }
                return !original.matches(application)
            }
        }
        // Every current cleanup target must have been in the preview with the same
        // process identity. This catches both newly launched apps and a process
        // replacement that happens to reuse a bundle ID (or PID).
        if hasCleanupDrift(currentTargets) {
            return "Cleanup was not applied: the running application list changed after preview. Refresh before applying cleanup."
        }

        var closed = 0
        var alreadyClosed = 0
        for target in expected {
            do {
                try Task.checkCancellation()
                let liveTargets = apps.runningApplications().filter {
                    !protected.contains($0.bundleID) && !managed.contains($0.bundleID)
                }
                if hasCleanupDrift(liveTargets) {
                    return "Cleanup stopped after \(applicationCount(closed)): the running application list changed during cleanup. Remaining applications were left open."
                }
                guard let currentTarget = apps.runningApplications().first(where: { $0.processID == target.processID }) else {
                    alreadyClosed += 1
                    continue
                }
                guard target.matches(currentTarget) else {
                    return "Cleanup stopped after \(applicationCount(closed)): \(target.appName) was replaced and was left running."
                }
                try await apps.terminate(target)
                try await waitUntilTerminated(target)
                closed += 1
            } catch is CancellationError {
                return "Cleanup cancelled after \(applicationCount(closed)). Remaining applications were left open."
            } catch {
                return "Cleanup stopped after \(applicationCount(closed)): \(error.localizedDescription)"
            }
        }
        if closed == 0, alreadyClosed == expected.count {
            return "Cleanup selected, but all previewed applications were already closed."
        }
        let closedText = "\(applicationCount(closed)) closed with a normal quit request."
        return alreadyClosed == 0
            ? closedText
            : "\(closedText) \(applicationCount(alreadyClosed)) was already closed."
    }

    private func applicationCount(_ count: Int) -> String {
        let noun = count == 1 ? "application" : "applications"
        return "\(count) \(noun)"
    }

    private func place(_ window: DesktopWindow, assignment: Assignment, protected: Set<String>) async throws {
        try Task.checkCancellation()
        try Protection.requireMutable(assignment.bundleID, additional: protected)
        let fresh = try await desktop.snapshot()
        guard let actual = fresh.windows.first(where: { $0.id == window.id }), actual == window else {
            throw PilotError.stale("Window changed before move. Refresh preview.")
        }
        try Protection.requireMutable(actual.bundleID, additional: protected)
        if actual.workspace != assignment.workspace { try await desktop.move(windowID: actual.id, to: assignment.workspace) }
        try await verify([actual.id], assignment: assignment)
    }
    private func verify(_ ids: [Int], assignment: Assignment) async throws {
        let snapshot = try await desktop.snapshot()
        guard !ids.isEmpty, ids.allSatisfy({ id in snapshot.windows.contains { $0.id == id && $0.bundleID == assignment.bundleID && $0.workspace == assignment.workspace } }) else {
            throw PilotError.unavailable("\(assignment.appName) did not reach \(assignment.workspace). Check AeroSpace is enabled and retry with a fresh preview.")
        }
    }
    private func waitForWindows(bundleID: String) async throws -> [DesktopWindow] {
        let deadline = ContinuousClock.now.advanced(by: .seconds(windowTimeout))
        repeat {
            try Task.checkCancellation()
            let windows = try await desktop.snapshot().windows.filter { $0.bundleID == bundleID }
            if !windows.isEmpty { return windows }
            try await Task.sleep(for: pollInterval)
        } while ContinuousClock.now < deadline
        throw PilotError.unavailable("Timed out waiting for \(bundleID) to open a window. Open its intended window, then preview again.")
    }
    private func waitUntilClosed(_ id: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(windowTimeout))
        repeat {
            try Task.checkCancellation()
            if try await !desktop.snapshot().windows.contains(where: { $0.id == id }) { return }
            try await Task.sleep(for: pollInterval)
        } while ContinuousClock.now < deadline
        throw PilotError.unavailable("Safari window \(id) is still open (close refused, cancelled, or waiting for confirmation). Further Safari work stopped.")
    }

    private func waitUntilTerminated(_ expected: RunningApplication) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(windowTimeout))
        repeat {
            try Task.checkCancellation()
            let running = apps.runningApplications()
            if let current = running.first(where: { $0.processID == expected.processID }) {
                guard expected.matches(current) else {
                    throw PilotError.stale("\(expected.appName) was replaced while quitting; the replacement was left running.")
                }
            } else {
                return
            }
            try await Task.sleep(for: pollInterval)
        } while ContinuousClock.now < deadline
        throw PilotError.unavailable("\(expected.appName) is still running (quit refused or waiting for confirmation).")
    }
}
