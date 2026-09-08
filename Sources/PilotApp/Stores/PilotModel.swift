import AppKit
import Observation
import UniformTypeIdentifiers
import PilotCore
import PilotIntegration
import PilotProfiles
import PilotOverview

@MainActor @Observable final class PilotModel {
    var profiles: [Profile] = []
    var selectedProfileID: UUID?
    var health: HealthReport?
    var plan: RestorePlan?
    var report: RestoreReport?
    var message: String?
    var messageIsError = false
    var busy = false
    var isRestoring = false
    var safariChoice: SafariChoice?
    var selectedWindows: [String: Int] = [:]
    var thumbnails: [Thumbnail] = []
    var previewWindowsByID: [Int: DesktopWindow] = [:]
    var showingSafariDecision = false
    var captureBusy = false
    var captureDuration: TimeInterval?
    let screenRecordingPermission: ScreenRecordingPermission
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var refreshingHealth = false
    @ObservationIgnored private let client = AeroSpaceClient()
    @ObservationIgnored private let store = ProfileStore(directory: JSONFiles.applicationSupport.appendingPathComponent("Profiles"))
    @ObservationIgnored private let tracker = VersionTracker(url: JSONFiles.applicationSupport.appendingPathComponent("versions.json"))
    @ObservationIgnored private let capture = WindowCaptureService()

    init(screenRecordingPermission: ScreenRecordingPermission = ScreenRecordingPermission()) {
        self.screenRecordingPermission = screenRecordingPermission
    }

    func refreshScreenRecordingPermission() {
        screenRecordingPermission.refresh()
        if !screenRecordingPermission.isGranted {
            capture.clear()
            thumbnails = []
            previewWindowsByID = [:]
            captureDuration = nil
        }
    }

    func enableScreenRecording() {
        guard !busy, !captureBusy else { return }
        screenRecordingPermission.enable()
        refreshScreenRecordingPermission()
    }

    var selectedProfile: Profile? { profiles.first { $0.id == selectedProfileID } }
    var canExport: Bool { !busy && selectedProfile != nil }
    func refresh() async {
        do {
            var loaded = try store.list()
            let work = try Profile.work()
            if !loaded.contains(where: { $0.id == work.id }) { loaded.insert(work, at: 0) }
            profiles = loaded
            if selectedProfileID == nil { selectedProfileID = loaded.first?.id }
        } catch { showError(error) }
        await refreshHealth()
    }
    func refreshHealth() async {
        refreshScreenRecordingPermission()
        guard !busy, !refreshingHealth else { return }
        refreshingHealth = true
        defer { refreshingHealth = false }
        do {
            health = await HealthChecker(client: client, manifest: try .bundled(), tracker: tracker).check()
        } catch { showError(error) }
    }
    func preview() async {
        guard !busy, let profile = selectedProfile else { return }
        busy = true
        defer { busy = false }
        do {
            let checker = HealthChecker(client: client, manifest: try .bundled(), tracker: tracker)
            let status = await checker.check()
            health = status
            guard status.canRestore, let snapshot = status.snapshot else { throw PilotError.unavailable(status.message) }
            plan = try RestorePlanner().plan(profile, snapshot: snapshot)
            report = nil; safariChoice = nil; selectedWindows = [:]; clearMessage()
        } catch { plan = nil; showError(error) }
    }
    func selectProfile() { plan = nil; report = nil; safariChoice = nil; selectedWindows = [:] }
    func beginApply() {
        guard !busy, let plan, plan.profile == selectedProfile else { return }
        if plan.items.contains(where: { $0.action == .safariDecision }) && safariChoice == nil {
            showingSafariDecision = true
            return
        }
        let resolutions = selectedWindows.compactMap { key, id -> WindowResolution? in
            guard let window = plan.snapshot.windows.first(where: { $0.id == id }) else { return nil }
            return WindowResolution(assignmentID: key, window: window)
        }
        let consent = safariChoice.map { SafariConsent(choice: $0, snapshot: plan.snapshot) }
        busy = true
        isRestoring = true
        applyTask = Task {
            defer { busy = false; isRestoring = false; applyTask = nil; self.plan = nil; safariChoice = nil }
            do {
                let checker = HealthChecker(client: client, manifest: try .bundled(), tracker: tracker)
                let engine = RestoreEngine(desktop: client, apps: MacApplications(client: client), preflight: {
                    let status = await checker.check()
                    guard status.canRestore else { throw PilotError.unavailable(status.message) }
                })
                report = try await engine.apply(plan, safariConsent: consent, resolutions: resolutions)
                clearMessage()
            } catch { showError(error) }
        }
    }
    func cancelRestore() { applyTask?.cancel() }
    func cancelSafariDecision() {
        showingSafariDecision = false
        safariChoice = nil
    }
    func confirmSafariDecision(_ choice: SafariChoice) {
        guard showingSafariDecision, !busy else { return }
        safariChoice = choice
        showingSafariDecision = false
        beginApply()
    }
    func importProfile() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let profile = try store.importProfile(from: url)
            profiles.removeAll { $0.id == profile.id }; profiles.append(profile)
            selectedProfileID = profile.id; selectProfile(); showSuccess("Imported \(profile.name).")
        } catch { showError(error) }
    }
    func exportProfile() {
        guard !busy, let profile = selectedProfile else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(profile.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.export(profile, to: url); showSuccess("Exported \(profile.name).") }
        catch { showError(error) }
    }
    func saveDesktop(name: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let profile = try store.capture(name: name, snapshot: await client.snapshot())
            try store.save(profile)
            profiles.append(profile); selectedProfileID = profile.id; selectProfile()
            showSuccess("Saved \(profile.name).")
        } catch { showError(error) }
    }
    func capturePreviews() async {
        guard !captureBusy, !busy else { return }
        refreshScreenRecordingPermission()
        guard screenRecordingPermission.isGranted else { return }
        captureBusy = true
        defer { captureBusy = false }
        do {
            let snapshot = try await client.snapshot()
            let start = Date()
            let captured = await capture.capture(snapshot.windows)
            refreshScreenRecordingPermission()
            guard screenRecordingPermission.isGranted else { return }
            thumbnails = captured
            previewWindowsByID = Dictionary(
                snapshot.windows.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            captureDuration = Date().timeIntervalSince(start)
            let suffix = thumbnails.count == 1 ? "" : "s"
            showSuccess("Updated \(thumbnails.count) window preview\(suffix).")
        } catch { showError(error) }
    }

    func dismissMessage() { clearMessage() }

    private func clearMessage() {
        message = nil
        messageIsError = false
    }

    private func showSuccess(_ text: String) {
        message = text
        messageIsError = false
    }

    private func showError(_ error: Error) {
        message = error.localizedDescription
        messageIsError = true
    }
}
