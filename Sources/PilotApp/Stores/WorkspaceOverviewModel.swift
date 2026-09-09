import Foundation
import Observation
import PilotCore
import PilotIntegration
import PilotOverview

struct WorkspaceOverviewMonitorSection: Identifiable, Equatable {
    let id: Int
    let name: String
    let workspaces: [OverviewWorkspace]
}

@MainActor @Observable final class WorkspaceOverviewModel {
    private enum PreferenceKey {
        static let groupByMonitor = "quickView.groupWorkspacesByMonitor"
        static let hideEmptyWorkspaces = "quickView.hideEmptyWorkspaces"
    }

    var query = ""
    var selectedWorkspace: String?
    var groupByMonitor: Bool {
        didSet { preferences.set(groupByMonitor, forKey: PreferenceKey.groupByMonitor) }
    }
    var hideEmptyWorkspaces: Bool {
        didSet { preferences.set(hideEmptyWorkspaces, forKey: PreferenceKey.hideEmptyWorkspaces) }
    }
    private(set) var snapshot: DesktopSnapshot?
    private(set) var thumbnails: [Int: Thumbnail] = [:]
    private(set) var loading = false
    private(set) var capturing = false
    private(set) var navigating = false
    private(set) var canCapture = false
    private(set) var error: String?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let readDesktop: @MainActor () async throws -> DesktopSnapshot
    @ObservationIgnored private let captureWindows: @MainActor ([DesktopWindow], @escaping @MainActor (Thumbnail) -> Void) async -> Void
    @ObservationIgnored private let hasPermission: () -> Bool
    @ObservationIgnored private let switchWorkspace: @MainActor (String) async throws -> Void
    @ObservationIgnored private let focusWindow: @MainActor (Int) async throws -> Void

    init(
        readDesktop: @escaping @MainActor () async throws -> DesktopSnapshot = { try await AeroSpaceClient().snapshot() },
        captureWindows: @escaping @MainActor ([DesktopWindow], @escaping @MainActor (Thumbnail) -> Void) async -> Void = { windows, update in
            _ = await WindowCaptureService().capture(windows, onThumbnail: update)
        },
        hasPermission: @escaping () -> Bool = { WindowCaptureService.hasPermission },
        switchWorkspace: @escaping @MainActor (String) async throws -> Void = { name in
            try await AeroSpaceClient().command(["workspace", "--", name])
        },
        focusWindow: @escaping @MainActor (Int) async throws -> Void = { try await AeroSpaceClient().focus(windowID: $0) },
        preferences: UserDefaults = .standard
    ) {
        self.preferences = preferences
        self.groupByMonitor = preferences.object(forKey: PreferenceKey.groupByMonitor) as? Bool ?? true
        self.hideEmptyWorkspaces = preferences.object(forKey: PreferenceKey.hideEmptyWorkspaces) as? Bool ?? false
        self.readDesktop = readDesktop
        self.captureWindows = captureWindows
        self.hasPermission = hasPermission
        self.switchWorkspace = switchWorkspace
        self.focusWindow = focusWindow
    }

    var groups: [OverviewWorkspace] {
        snapshot.map {
            OverviewWorkspace.groups(in: $0, matching: query, includingEmpty: !hideEmptyWorkspaces)
        } ?? []
    }

    var hasMultipleMonitors: Bool { (snapshot?.monitors.count ?? 0) > 1 }

    var monitorSections: [WorkspaceOverviewMonitorSection] {
        guard let snapshot, hasMultipleMonitors, groupByMonitor else { return [] }
        let grouped = Dictionary(grouping: groups, by: \.monitorID)
        let order = snapshot.monitors.map(\.id)
        return grouped.keys.sorted { left, right in
            let leftIndex = order.firstIndex(of: left) ?? order.count
            let rightIndex = order.firstIndex(of: right) ?? order.count
            if leftIndex != rightIndex { return leftIndex < rightIndex }
            return left < right
        }.map { monitorID in
            let name = snapshot.monitors.first(where: { $0.id == monitorID })?.name ?? "Display unknown"
            let workspaces = (grouped[monitorID] ?? []).sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return WorkspaceOverviewMonitorSection(id: monitorID, name: name, workspaces: workspaces)
        }
    }

    var usesMonitorGrouping: Bool { groupByMonitor && hasMultipleMonitors }

    func load() async {
        let request = UUID()
        generation = request
        loading = true; capturing = false; error = nil
        thumbnails = [:]
        canCapture = hasPermission()
        defer { if generation == request { loading = false; capturing = false } }
        do {
            let desktop = try await readDesktop()
            guard !Task.isCancelled, generation == request else { return }
            snapshot = desktop
            reconcileSelection()
            loading = false
            guard canCapture else { return }
            capturing = true
            await captureWindows(desktop.windows) { [weak self] thumbnail in
                guard let self, !Task.isCancelled, self.generation == request else { return }
                guard self.hasPermission() else {
                    self.canCapture = false; self.thumbnails = [:]
                    return
                }
                self.thumbnails[thumbnail.windowID] = thumbnail
            }
        } catch {
            guard !Task.isCancelled, generation == request else { return }
            snapshot = nil
            self.error = error.localizedDescription
        }
    }

    func invalidate() {
        generation = UUID()
        snapshot = nil; thumbnails = [:]; query = ""; selectedWorkspace = nil
        loading = false; capturing = false; navigating = false; error = nil
    }

    func reconcileSelection() {
        let available = groups
        if !available.contains(where: { $0.name == selectedWorkspace }) {
            selectedWorkspace = available.first(where: \.isVisible)?.name ?? available.first?.name
        }
    }

    func moveSelection(_ offset: Int) {
        let available = groups
        guard !available.isEmpty else { return }
        let index = available.firstIndex { $0.name == selectedWorkspace } ?? 0
        selectedWorkspace = available[(index + offset % available.count + available.count) % available.count].name
    }

    /// Revalidate the selected item before switching; never move or close windows.
    func activate(workspace: String, window: DesktopWindow? = nil) async -> Bool {
        guard !navigating else { return false }
        let request = generation
        navigating = true; error = nil
        defer { if generation == request { navigating = false } }
        do {
            let current = try await readDesktop()
            guard !Task.isCancelled, generation == request else { return false }
            if let window {
                guard let live = current.windows.first(where: { $0.id == window.id }),
                      live.bundleID == window.bundleID, live.title == window.title,
                      live.workspace == window.workspace else {
                    throw PilotError.stale("That window changed or closed. Refresh the overview and select it again.")
                }
                try await focusWindow(live.id)
            } else {
                guard current.workspaces.contains(where: { $0.name == workspace })
                        || current.windows.contains(where: { $0.workspace == workspace }) else {
                    throw PilotError.stale("That workspace is no longer available. Refresh the overview.")
                }
                try await switchWorkspace(workspace)
            }
            return generation == request && !Task.isCancelled
        } catch {
            if generation == request && !Task.isCancelled { self.error = error.localizedDescription }
            return false
        }
    }
}
