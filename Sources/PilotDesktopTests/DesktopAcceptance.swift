import AppKit
import PilotCore
import PilotIntegration
import PilotProfiles
import PilotOverview

private struct Blocked: Error { let reason: String }

@main struct DesktopAcceptance {
    @MainActor static func main() async {
        do {
            guard ProcessInfo.processInfo.environment["PILOT_DESKTOP_TEST_SESSION"] == "1" else {
                throw Blocked(reason: "Dedicated desktop test session is not enabled.")
            }
            NSApplication.shared.setActivationPolicy(.prohibited)
            let args = Array(CommandLine.arguments.dropFirst())
            guard args.count == 2 else { throw PilotError.invalid("Usage: pilot-desktop-tests CHECK PROJECT_ROOT") }
            let runner = DesktopRunner(root: URL(fileURLWithPath: args[1]))
            try await runner.run(args[0])
        } catch let error as Blocked { print("BLOCKED: \(error.reason)"); exit(3) }
        catch { fputs("FAILED: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}

@MainActor private final class DesktopRunner {
    let root: URL
    let client = AeroSpaceClient()
    let fixtureID = "uk.jason.aerospace-pilot.fixture"
    let destinations = ["Pilot Fixture Red": "pilot-test-red", "Pilot Fixture Green": "pilot-test-green", "Pilot Fixture Blue": "pilot-test-blue"]
    init(root: URL) { self.root = root }
    func require(_ condition: @autoclosure () -> Bool, _ detail: String) throws {
        guard condition() else { throw PilotError.invalid(detail) }
    }
    func run(_ check: String) async throws {
        let health = await HealthChecker(client: client, manifest: try .bundled()).check()
        guard health.canRestore else { throw Blocked(reason: health.message) }
        if check == "work-placement" { try await workPlacement(); return }
        if check.hasPrefix("capture") && !WindowCaptureService.hasPermission {
            throw Blocked(reason: "Screen Recording permission is not granted to this desktop runner.")
        }
        if check == "capture-conditions" && NSScreen.screens.count < 2 {
            throw Blocked(reason: "The capture conditions lane requires two physical displays.")
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: fixtureID).isEmpty else {
            throw Blocked(reason: "A fixture app is already running. Close that test instance before running a new test.")
        }
        let before = try await client.snapshot()
        guard !before.windows.contains(where: { destinations.values.contains($0.workspace) }) else {
            throw Blocked(reason: "Reserved pilot-test-* workspaces contain existing windows.")
        }
        let originalWorkspace = try await client.command(["list-workspaces", "--focused"]).trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let windows = try await launchFixture()
            try await placeFixture(windows)
            if check == "controlled-windows" {
                for window in windows {
                    try await client.focus(windowID: window.id)
                    let focused = try await client.command(["list-windows", "--focused", "--format", "%{window-id}"]).trimmingCharacters(in: .whitespacesAndNewlines)
                    try require(focused == String(window.id), "Focus command did not activate fixture \(window.id).")
                }
            } else if check == "capture-three-workspaces" || check == "capture-conditions" {
                try await captureFixture()
                if check == "capture-conditions" {
                    // This additional lane cannot be certified by substituting fixture-only permission tests.
                    throw Blocked(reason: "Fresh three-workspace capture passed; minimized/occluded, permission-revocation and Work-app capture matrix still needs an automated desktop scenario. This requirement is not signed off.")
                }
            } else if check == "profile-relaunch" {
                try await relaunchProfile()
            } else { throw PilotError.invalid("Unknown desktop check \(check).") }
            try await closeFixture()
            if !originalWorkspace.isEmpty { try await client.command(["workspace", "--", originalWorkspace]) }
            print("PASS: \(check)")
        } catch {
            try? await closeFixture()
            if !originalWorkspace.isEmpty { _ = try? await client.command(["workspace", "--", originalWorkspace]) }
            throw error
        }
    }
    func launchFixture() async throws -> [DesktopWindow] {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        _ = try await NSWorkspace.shared.openApplication(at: root.appendingPathComponent("dist/Pilot Window Fixture.app"), configuration: config)
        for _ in 0..<60 {
            let windows = try await client.snapshot().windows.filter { $0.bundleID == fixtureID }
            if windows.count == 3 && Set(windows.map(\.title)) == Set(destinations.keys) { return windows }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw PilotError.unavailable("Fixture did not register exactly three expected windows in AeroSpace.")
    }
    func closeFixture() async throws {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: fixtureID) { app.terminate() }
        for _ in 0..<50 {
            if NSRunningApplication.runningApplications(withBundleIdentifier: fixtureID).isEmpty { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw PilotError.unavailable("Fixture did not terminate normally.")
    }
    func placeFixture(_ windows: [DesktopWindow]) async throws {
        for window in windows {
            guard window.bundleID == fixtureID, let destination = destinations[window.title] else { throw PilotError.invalid("Unexpected fixture identity.") }
            try await client.move(windowID: window.id, to: destination)
        }
        let current = try await client.snapshot()
        for window in windows {
            try require(current.windows.contains { $0.id == window.id && $0.workspace == destinations[window.title] }, "Fixture placement failed. Enable AeroSpace.")
        }
    }
    func captureFixture() async throws {
        let before = try await client.snapshot()
        let focus = try await client.command(["list-workspaces", "--focused"])
        let windows = before.windows.filter { $0.bundleID == fixtureID }
        let start = Date()
        let results = await WindowCaptureService().capture(windows)
        let folder = root.appendingPathComponent("artifacts/desktop-capture/\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try require(results.count == 3, "Three fixture images are required.")
        for result in results {
            guard result.state == .fresh, let png = result.png,
                  let window = windows.first(where: { $0.id == result.windowID }) else {
                throw PilotError.unavailable("Fresh fixture capture failed: \(result.reason ?? "no image")")
            }
            try png.write(to: folder.appendingPathComponent("\(result.windowID).png"))
            try verifyPattern(png, title: window.title)
        }
        let after = try await client.snapshot()
        let afterFocus = try await client.command(["list-workspaces", "--focused"])
        try require(before == after && focus == afterFocus, "Capture changed window assignments, monitor mapping or workspace focus.")
        try JSONFiles.write(["seconds": Date().timeIntervalSince(start), "verifiedPatterns": 3], to: folder.appendingPathComponent("evidence.json"))
        print("Three fresh images matched fixture colors, white inset and black center. Evidence: \(folder.path)")
    }
    func verifyPattern(_ data: Data, title: String) throws {
        guard let image = NSBitmapImageRep(data: data), image.pixelsWide > 100, image.pixelsHigh > 100 else {
            throw PilotError.invalid("Image is too small to validate a fixture pattern.")
        }
        func sample(_ x: Double, _ y: Double) throws -> NSColor {
            guard let color = image.colorAt(x: Int(Double(image.pixelsWide) * x), y: Int(Double(image.pixelsHigh) * y))?.usingColorSpace(.deviceRGB) else {
                throw PilotError.invalid("Cannot read fixture pixels.")
            }
            return color
        }
        let border = try sample(0.12, 0.55)
        let white = try sample(0.32, 0.55)
        let black = try sample(0.5, 0.55)
        let channels = [border.redComponent, border.greenComponent, border.blueComponent]
        let expected = title.hasSuffix("Red") ? 0 : title.hasSuffix("Green") ? 1 : 2
        try require(channels[expected] > 0.65 && channels.enumerated().allSatisfy { $0.offset == expected || $0.element < 0.35 }, "Wrong fixture color for \(title).")
        try require(min(white.redComponent, white.greenComponent, white.blueComponent) > 0.7, "Fixture white inset missing.")
        try require(max(black.redComponent, black.greenComponent, black.blueComponent) < 0.3, "Fixture black center missing.")
    }
    func relaunchProfile() async throws {
        let original = try await client.snapshot()
        let fixtureOnly = DesktopSnapshot(windows: original.windows.filter { $0.bundleID == fixtureID }, workspaces: original.workspaces, monitors: original.monitors)
        let store = ProfileStore(directory: root.appendingPathComponent("artifacts/desktop-profiles"))
        let profile = try store.capture(name: "Fixture relaunch", snapshot: fixtureOnly)
        let path = try store.save(profile)
        let loaded = try store.load(path)
        let previousIDs = Set(fixtureOnly.windows.map(\.id))
        try await closeFixture()
        let newWindows = try await launchFixture()
        try require(previousIDs.isDisjoint(with: Set(newWindows.map(\.id))), "Fixture runtime IDs did not change; relaunch proof is inconclusive.")
        let checker = HealthChecker(client: client, manifest: try .bundled())
        let engine = RestoreEngine(desktop: client, apps: MacApplications(client: client), preflight: {
            let report = await checker.check()
            guard report.canRestore else { throw PilotError.unavailable(report.message) }
        })
        for _ in 0..<2 {
            let plan = try await RestorePlanner().plan(loaded, snapshot: client.snapshot())
            let report = try await engine.apply(plan)
            try require(report.allPlacementsVerified, report.summary)
            let after = try await client.snapshot()
            try require(after.windows.filter { $0.bundleID == fixtureID }.count == 3, "Relaunch/reapply created duplicate windows.")
        }
    }
    func workPlacement() async throws {
        guard ProcessInfo.processInfo.environment["PILOT_ALLOW_WORK_RESTORE"] == "1" else {
            throw Blocked(reason: "Set PILOT_ALLOW_WORK_RESTORE=1 only in the dedicated account to authorize the bundled example Work placement and Safari move-all acceptance scenario.")
        }
        let profile = try Profile.work()
        let apps = MacApplications(client: client)
        for assignment in profile.assignments where !apps.isInstalled(bundleID: assignment.bundleID) {
            throw Blocked(reason: "Work acceptance requires installed app \(assignment.bundleID).")
        }
        let initial = try await client.snapshot()
        let protectedWindows = initial.windows.filter { Protection.required.contains($0.bundleID) }
        let running = Dictionary(uniqueKeysWithValues: Protection.required.map { ($0, apps.isRunning(bundleID: $0)) })
        let checker = HealthChecker(client: client, manifest: try .bundled())
        let engine = RestoreEngine(desktop: client, apps: apps, preflight: {
            let report = await checker.check()
            guard report.canRestore else { throw PilotError.unavailable(report.message) }
        })
        var firstIDs: Set<Int>?
        for _ in 0..<2 {
            let snapshot = try await client.snapshot()
            let report = try await engine.apply(RestorePlanner().plan(profile, snapshot: snapshot), safariConsent: .init(choice: .moveAll, snapshot: snapshot))
            try require(report.allPlacementsVerified, "Real Work placement is incomplete: \(report.summary)")
            let after = try await client.snapshot()
            try require(after.windows.filter { Protection.required.contains($0.bundleID) } == protectedWindows, "Protected app windows changed.")
            try require(Protection.required.allSatisfy { apps.isRunning(bundleID: $0) == running[$0] }, "Protected app running state changed.")
            let ids = Set(after.windows.filter { window in profile.assignments.contains { $0.bundleID == window.bundleID } }.map(\.id))
            if let firstIDs { try require(firstIDs == ids, "Repeat apply changed Work window count or identities.") }
            firstIDs = ids
        }
        print("PASS: real Work placements and repeat apply. ChatGPT window/running-state invariants held. Safari used explicitly authorized move-all.")
    }
}
