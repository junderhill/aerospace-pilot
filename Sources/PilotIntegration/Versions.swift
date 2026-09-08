import Foundation
import PilotCore

public struct AeroSpaceVersion: Codable, Equatable, Sendable {
    public let raw: String
    public let major: Int?
    public let minor: Int?
    public let patch: Int?
    public let prerelease: String?
    public let hash: String?
    public init(raw: String) {
        self.raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = self.raw.split(separator: " ").map(String.init)
        let parts = (tokens.first ?? "").split(separator: "-", maxSplits: 1).map(String.init)
        let numbers = (parts.first ?? "").split(separator: ".").map(String.init)
        major = numbers.count == 3 ? Int(numbers[0]) : nil
        minor = numbers.count == 3 ? Int(numbers[1]) : nil
        patch = numbers.count == 3 ? Int(numbers[2]) : nil
        prerelease = parts.count == 2 ? parts[1] : nil
        hash = tokens.count > 1 ? tokens[1] : nil
    }
}

public struct VersionPair: Codable, Equatable, Sendable {
    public let client: AeroSpaceVersion
    public let server: AeroSpaceVersion
    public init(client: String, server: String) {
        self.client = AeroSpaceVersion(raw: client); self.server = AeroSpaceVersion(raw: server)
    }
    public init(output: String) throws {
        let lines = output.components(separatedBy: .newlines)
        func value(_ prefix: String) -> String? {
            lines.first(where: { $0.lowercased().hasPrefix(prefix.lowercased()) })?
                .dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        }
        guard let client = value("aerospace CLI client version:"), !client.isEmpty,
              let server = value("AeroSpace.app server version:"), !server.isEmpty,
              !server.hasPrefix("Unknown") else {
            throw PilotError.unavailable("AeroSpace did not return both client and server versions. Start or reconnect AeroSpace.")
        }
        self.init(client: client, server: server)
    }
    public var matches: Bool { client == server }
    public var label: String { "CLI \(client.raw); server \(server.raw)" }
}

public struct CompatibilityManifest: Codable, Sendable {
    public var schemaVersion: Int
    public var testedPairs: [VersionPair]
    public var requiredCapabilities: [String]
    public init(testedPairs: [VersionPair]) {
        self.schemaVersion = 1; self.testedPairs = testedPairs
        self.requiredCapabilities = ["windows-json", "workspaces-json", "monitors-json"]
    }
    public static func bundled() throws -> Self {
        let resources = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("AeroSpacePilot_PilotIntegration.bundle")) } ?? Bundle.module
        guard let url = resources.url(forResource: "compatibility", withExtension: "json") else { throw PilotError.unavailable("Compatibility manifest is missing.") }
        let value = try JSONFiles.decode(Self.self, from: Data(contentsOf: url))
        guard value.schemaVersion == 1 else { throw PilotError.invalid("Unsupported compatibility manifest.") }
        return value
    }
}

public actor VersionTracker {
    struct State: Codable { var last: VersionPair; var pendingNotice: String? }
    public struct Observation: Sendable { public let notice: String?; public let isNew: Bool }
    private let url: URL
    public init(url: URL) { self.url = url }
    public func observe(_ pair: VersionPair) throws -> Observation {
        let state: State?
        if FileManager.default.fileExists(atPath: url.path) {
            state = try JSONFiles.decode(State.self, from: Data(contentsOf: url))
        } else { state = nil }
        let changed = state.map { $0.last != pair } ?? false
        let notice = changed ? "AeroSpace changed from \(state!.last.label) to \(pair.label). Check Pilot compatibility before restoring." : state?.pendingNotice
        try JSONFiles.write(State(last: pair, pendingNotice: notice), to: url)
        return Observation(notice: notice, isNew: changed)
    }
    public func acknowledge() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var state = try JSONFiles.decode(State.self, from: Data(contentsOf: url))
        state.pendingNotice = nil
        try JSONFiles.write(state, to: url)
    }
}
