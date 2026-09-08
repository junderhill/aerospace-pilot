import Foundation
import PilotCore

public struct HealthReport: Codable, Sendable {
    public enum State: String, Codable, Sendable { case executableMissing, serverUnavailable, unresponsive, reachable, incompatible }
    public var state: State
    public var message: String
    public var versions: VersionPair?
    public var warnings: [String]
    public var windowManagement: String
    public var snapshot: DesktopSnapshot?
    public var canRestore: Bool { state == .reachable }
}

public struct HealthChecker: Sendable {
    public let client: AeroSpaceClient
    public let manifest: CompatibilityManifest
    public let tracker: VersionTracker?
    public init(client: AeroSpaceClient, manifest: CompatibilityManifest, tracker: VersionTracker? = nil) {
        self.client = client; self.manifest = manifest; self.tracker = tracker
    }
    public func check() async -> HealthReport {
        var pair: VersionPair?
        do {
            // Snapshot probes are read-only and prove that the server is reachable.
            let snapshot = try await client.snapshot()
            pair = try await client.versions()
            guard let pair else { throw PilotError.unavailable("Version pair is unavailable.") }
            var warnings: [String] = []
            if let tracker {
                do { if let notice = try await tracker.observe(pair).notice { warnings.append(notice) } }
                catch { warnings.append("Cannot persist version observations: \(error.localizedDescription)") }
            }
            if !pair.matches {
                return HealthReport(state: .incompatible, message: "AeroSpace CLI and running app disagree. Align the installation and restart AeroSpace.", versions: pair,
                                    warnings: warnings, windowManagement: "unknown", snapshot: snapshot)
            }
            if !manifest.testedPairs.contains(pair) {
                warnings.append("This Pilot release has not been certified with \(pair.client.raw); Pilot may need an update. Read-only capability probes passed.")
            }
            return HealthReport(state: .reachable, message: "AeroSpace is reachable.", versions: pair, warnings: warnings,
                                windowManagement: "unknown — AeroSpace must be enabled before placement", snapshot: snapshot)
        } catch {
            let state: HealthReport.State
            if let command = error as? CommandFailure {
                switch command.kind {
                case .missingExecutable: state = .executableMissing
                case .timeout: state = .unresponsive
                case .malformedResponse: state = .incompatible
                default: state = .serverUnavailable
                }
            } else { state = .incompatible }
            return HealthReport(state: state, message: error.localizedDescription, versions: pair, warnings: [], windowManagement: "unknown", snapshot: nil)
        }
    }
}
