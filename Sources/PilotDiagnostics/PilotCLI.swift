import AppKit
import PilotCore
import PilotIntegration
import PilotProfiles
import PilotOverview

@main struct PilotCLI {
    @MainActor static func main() async {
        do { try await run(Array(CommandLine.arguments.dropFirst())) }
        catch { fputs("pilot: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    @MainActor static func run(_ arguments: [String]) async throws {
        let client = AeroSpaceClient()
        func printJSON<T: Encodable>(_ value: T) throws {
            print(String(decoding: try JSONFiles.encode(value), as: UTF8.self))
        }
        switch arguments.first {
        case "health", "doctor":
            let tracker: VersionTracker?
            if let index = arguments.firstIndex(of: "--state-file"), arguments.indices.contains(index + 1) {
                tracker = VersionTracker(url: URL(fileURLWithPath: arguments[index + 1]))
            } else { tracker = nil }
            let report = await HealthChecker(client: client, manifest: try .bundled(), tracker: tracker).check()
            if arguments.first == "doctor" {
                struct Doctor: Encodable { let health: HealthReport; let screenRecording: Bool; let accessibility: Bool; let displays: Int; let installedApps: [String: Bool] }
                let apps = MacApplications(client: client)
                let work = try Profile.work()
                try printJSON(Doctor(health: report, screenRecording: WindowCaptureService.hasPermission, accessibility: AXIsProcessTrusted(),
                                     displays: NSScreen.screens.count, installedApps: Dictionary(uniqueKeysWithValues: work.assignments.map { ($0.bundleID, apps.isInstalled(bundleID: $0.bundleID)) })))
            } else { try printJSON(report) }
            if !report.canRestore { exit(1) }
        case "snapshot": try printJSON(await client.snapshot())
        case "work": try printJSON(Profile.work())
        case "validate":
            guard arguments.count == 2 else { throw PilotError.invalid("Usage: pilot validate PROFILE.json") }
            let profile = try ProfileStore.decode(Data(contentsOf: URL(fileURLWithPath: arguments[1])))
            print("Valid schema \(profile.schemaVersion): \(profile.name), \(profile.assignments.count) assignments.")
        case "preview":
            let profile = try arguments.count == 2 ? ProfileStore.decode(Data(contentsOf: URL(fileURLWithPath: arguments[1]))) : Profile.work()
            let plan = try await RestorePlanner().plan(profile, snapshot: client.snapshot())
            for item in plan.items { print("\(item.assignment.appName) → \(item.assignment.workspace): \(item.action.rawValue). \(item.detail)") }
            for warning in plan.warnings { print(warning) }
        case "capture":
            // ScreenCaptureKit needs a WindowServer/AppKit connection even in a CLI process.
            NSApplication.shared.setActivationPolicy(.prohibited)
            guard let index = arguments.firstIndex(of: "--output"), arguments.indices.contains(index + 1) else {
                throw PilotError.invalid("Usage: pilot capture --output DIRECTORY [--bundle-id ID]")
            }
            let output = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            let before = try await client.snapshot()
            var windows = before.windows
            if let index = arguments.firstIndex(of: "--bundle-id"), arguments.indices.contains(index + 1) {
                windows = windows.filter { $0.bundleID == arguments[index + 1] }
            }
            let start = Date()
            let results = await WindowCaptureService().capture(windows)
            struct Evidence: Encodable {
                struct Item: Encodable { let windowID: Int; let state: String; let age: TimeInterval?; let reason: String?; let file: String? }
                let items: [Item]; let seconds: Double; let layoutUnchanged: Bool
            }
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            var items: [Evidence.Item] = []
            for result in results {
                let filename = "window-\(result.windowID).png"
                if let png = result.png { try png.write(to: output.appendingPathComponent(filename), options: .atomic) }
                items.append(.init(windowID: result.windowID, state: result.state.rawValue, age: result.age(), reason: result.reason,
                                   file: result.png == nil ? nil : filename))
            }
            let after = try await client.snapshot()
            let evidence = Evidence(items: items, seconds: Date().timeIntervalSince(start), layoutUnchanged: before == after)
            try JSONFiles.write(evidence, to: output.appendingPathComponent("capture.json"))
            try printJSON(evidence)
            if results.isEmpty || results.contains(where: { $0.state != .fresh }) || !evidence.layoutUnchanged { exit(3) }
        default:
            print("Usage: pilot {health|doctor|snapshot|work|validate FILE|preview [FILE]|capture --output DIR [--bundle-id ID]}\nProfile application is available through the app's explicit preview and Safari decision workflow.")
            if !arguments.isEmpty && arguments.first != "--help" { exit(2) }
        }
    }
}
