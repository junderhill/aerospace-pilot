import SwiftUI
import PilotIntegration

struct ConnectionStatusView: View {
    let health: HealthReport?

    var body: some View {
        GroupBox {
            if let health {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: statusIcon(for: health))
                        .font(.title2)
                        .foregroundStyle(statusColor(for: health))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(statusTitle(for: health))
                            .font(.headline)

                        Text(statusSummary(for: health))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        ForEach(displayWarnings(health.warnings), id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let versions = health.versions {
                            DisclosureGroup("Connection details") {
                                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                                    GridRow {
                                        Text("CLI")
                                            .foregroundStyle(.secondary)
                                        Text(connectionLabel(versions.client))
                                            .textSelection(.enabled)
                                    }
                                    GridRow {
                                        Text("App")
                                            .foregroundStyle(.secondary)
                                        Text(connectionLabel(versions.server))
                                            .textSelection(.enabled)
                                    }
                                }
                                .font(.caption.monospaced())
                                .padding(.top, 6)
                            }
                            .font(.callout)
                        }
                    }

                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking AeroSpace…")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func statusTitle(for health: HealthReport) -> String {
        switch health.state {
        case .reachable: "AeroSpace connected"
        case .incompatible: "AeroSpace versions do not match"
        case .executableMissing: "AeroSpace CLI not found"
        case .serverUnavailable: "AeroSpace is not running"
        case .unresponsive: "AeroSpace is not responding"
        }
    }

    private func statusSummary(for health: HealthReport) -> String {
        guard health.canRestore, let versions = health.versions else {
            return health.message
        }

        let version = versions.client.raw.split(separator: " ").first.map(String.init) ?? versions.client.raw
        guard let snapshot = health.snapshot else { return "AeroSpace \(version)" }
        return [
            "AeroSpace \(version)",
            count(snapshot.monitors.count, singular: "display"),
            count(snapshot.windows.count, singular: "window"),
        ].joined(separator: " · ")
    }

    private func statusIcon(for health: HealthReport) -> String {
        switch health.state {
        case .reachable: "checkmark.circle.fill"
        case .incompatible: "exclamationmark.triangle.fill"
        case .executableMissing, .serverUnavailable, .unresponsive: "xmark.circle.fill"
        }
    }

    private func statusColor(for health: HealthReport) -> Color {
        switch health.state {
        case .reachable: .green
        case .incompatible: .orange
        case .executableMissing, .serverUnavailable, .unresponsive: .red
        }
    }

    private func displayWarnings(_ warnings: [String]) -> [String] {
        warnings.map { warning in
            if warning.contains("has not been certified") {
                return "This AeroSpace version has not been verified with Pilot yet."
            }
            if warning.contains("Cannot persist version observations") {
                return "Pilot could not save the latest version check."
            }
            return warning
        }
    }

    private func count(_ value: Int, singular: String) -> String {
        "\(value) \(singular)\(value == 1 ? "" : "s")"
    }

    private func connectionLabel(_ version: AeroSpaceVersion) -> String {
        let number = version.raw.split(separator: " ").first.map(String.init) ?? version.raw
        guard let hash = version.hash else { return number }
        return "\(number) · \(hash.prefix(8))"
    }
}
