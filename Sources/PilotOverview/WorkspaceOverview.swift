import Foundation
import PilotCore

public struct OverviewWorkspace: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let monitorName: String
    public let isVisible: Bool
    public let windows: [DesktopWindow]

    public static func groups(in snapshot: DesktopSnapshot, matching query: String = "") -> [Self] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let windows = snapshot.windows.filter { $0.bundleID != Protection.pilot }
        let names = Set(snapshot.workspaces.map(\.name)).union(windows.map(\.workspace))
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.compactMap { name in
            let workspace = snapshot.workspaces.first { $0.name == name }
            let members = windows.filter { $0.workspace == name }.sorted {
                if $0.appName != $1.appName { return $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
                if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                return $0.id < $1.id
            }
            let matches = members.filter {
                query.isEmpty || name.localizedCaseInsensitiveContains(query)
                    || $0.appName.localizedCaseInsensitiveContains(query)
                    || $0.title.localizedCaseInsensitiveContains(query)
            }
            guard query.isEmpty || name.localizedCaseInsensitiveContains(query) || !matches.isEmpty else { return nil }
            let monitorID = workspace?.monitorID ?? members.first?.monitorID
            let monitor = snapshot.monitors.first { $0.id == monitorID }?.name ?? "Display unknown"
            return Self(name: name, monitorName: monitor, isVisible: workspace?.isVisible ?? false, windows: matches)
        }
    }
}
