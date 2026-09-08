import Foundation
import PilotCore

public struct ProfileStore: Sendable {
    public let directory: URL
    public let globalProtections: Set<String>
    public init(directory: URL, globalProtections: Set<String> = []) {
        self.directory = directory; self.globalProtections = globalProtections
    }
    public static func decode(_ data: Data, globalProtections: Set<String> = []) throws -> Profile {
        struct Header: Decodable { let schemaVersion: Int }
        let header = try JSONFiles.decode(Header.self, from: data)
        guard header.schemaVersion == 1 else { throw PilotError.invalid("Unsupported profile schema \(header.schemaVersion). No changes made.") }
        let profile = try JSONFiles.decode(Profile.self, from: data)
        try profile.validate(globalProtections: globalProtections)
        return profile
    }
    public func load(_ url: URL) throws -> Profile { try Self.decode(Data(contentsOf: url), globalProtections: globalProtections) }
    public func list() throws -> [Profile] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map(load).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    @discardableResult public func save(_ profile: Profile) throws -> URL {
        try profile.validate(globalProtections: globalProtections)
        let url = directory.appendingPathComponent(profile.id.uuidString).appendingPathExtension("json")
        try JSONFiles.write(profile, to: url)
        return url
    }
    public func export(_ profile: Profile, to url: URL) throws {
        try profile.validate(globalProtections: globalProtections)
        try JSONFiles.write(profile, to: url)
    }
    @discardableResult public func importProfile(from url: URL) throws -> Profile {
        let profile = try load(url) // Complete validation before any mutation.
        try save(profile)
        return profile
    }
    public func capture(name: String, snapshot: DesktopSnapshot) throws -> Profile {
        let excluded = Protection.required.union(globalProtections).union([Protection.pilot])
        var windows = snapshot.windows.filter { !excluded.contains($0.bundleID) }.sorted { $0.id < $1.id }
        let safari = windows.filter { $0.bundleID == Protection.safari }
        if safari.count > 1 {
            guard Set(safari.map(\.workspace)).count == 1 else {
                throw PilotError.invalid("Safari spans several workspaces. Its all-window policy needs one destination; save a profile after choosing that destination.")
            }
            windows.removeAll { $0.bundleID == Protection.safari && $0.id != safari[0].id }
        }
        let groups = Dictionary(grouping: windows, by: \.bundleID)
        let assignments = windows.map { window in
            Assignment(bundleID: window.bundleID, appName: window.appName, workspace: window.workspace,
                       identity: (groups[window.bundleID]?.count ?? 0) > 1 ? WindowIdentity(exactTitle: window.title) : nil,
                       preferredMonitorName: snapshot.monitors.first { $0.id == window.monitorID }?.name)
        }
        let profile = Profile(name: name, assignments: assignments, protectedBundleIDs: Protection.required.union(globalProtections).sorted())
        try profile.validate(globalProtections: globalProtections)
        return profile
    }
}
