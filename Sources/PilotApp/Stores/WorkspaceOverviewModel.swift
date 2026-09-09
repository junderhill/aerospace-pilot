import Foundation
import Observation
import PilotCore
import PilotIntegration
import PilotOverview

@MainActor @Observable final class WorkspaceOverviewModel {
    var query = ""
    var selectedWorkspace: String?
    private(set) var snapshot: DesktopSnapshot?
    private(set) var thumbnails: [Int: Thumbnail] = [:]
    private(set) var loading = false
    private(set) var capturing = false
    private(set) var navigating = false
    private(set) var canCapture = false
    private(set) var error: String?
    @ObservationIgnored private var generation = UUID()
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
        focusWindow: @escaping @MainActor (Int) async throws -> Void = { try await AeroSpaceClient().focus(windowID: $0) }
    ) {
        self.readDesktop = readDesktop
        self.captureWindows = captureWindows
        self.hasPermission = hasPermission
        self.switchWorkspace = switchWorkspace
        self.focusWindow = focusWindow
    }

    var groups: [OverviewWorkspace] { snapshot.map { OverviewWorkspace.groups(in: $0, matching: query) } ?? [] }

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
