import SwiftUI
import PilotProfiles

struct RestorePreviewView: View {
    @Bindable var model: PilotModel
    let plan: RestorePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label("Restore preview", systemImage: "list.bullet.clipboard")
                    .font(.title2.bold())
                Spacer(minLength: 12)
                Text("\(plan.items.count) apps")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }

            Text("Review each action before applying \(plan.profile.name).")
                .foregroundStyle(.secondary)

            if !plan.workspaceMonitorTargets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Workspace displays", systemImage: "display.2")
                        .font(.headline)
                    ForEach(plan.workspaceMonitorTargets) { workspace in
                        HStack(spacing: 8) {
                            Text(workspace.name)
                                .font(.body.monospaced().weight(.medium))
                            Text("→ \(workspace.preferredMonitorName ?? "current display mapping")")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Close applications outside this layout", isOn: $model.closeAppsOutsideLayout)
                    .toggleStyle(.checkbox)
                    .disabled(model.busy)
                Text(cleanupDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !plan.cleanupCandidates.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(plan.cleanupCandidates) { application in
                            Label(application.appName, systemImage: "power")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("\(application.bundleID) · process \(application.processID)")
                        }
                    }
                    .padding(.leading, 4)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))

            VStack(spacing: 0) {
                ForEach(plan.items) { item in
                    RestorePreviewRow(model: model, plan: plan, item: item)
                    if item.id != plan.items.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.quaternary)
            }

            ForEach(plan.warnings, id: \.self) { warning in
                Label(warning, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var cleanupDescription: String {
        if plan.cleanupCandidates.isEmpty {
            return "No other regular applications are running."
        }
        if model.closeAppsOutsideLayout {
            return "Only the applications listed below receive a normal quit request. Save dialogs and applications launched after this preview are left alone."
        }
        return "If enabled, only the applications listed below will receive a normal quit request."
    }
}

private struct RestorePreviewRow: View {
    @Bindable var model: PilotModel
    let plan: RestorePlan
    let item: PlanItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(item.assignment.appName, systemImage: item.action.systemImage)
                    .font(.headline)
                Spacer(minLength: 8)
                Text(actionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.action.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(item.action.tint.opacity(0.1), in: Capsule())
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Workspace \(item.assignment.workspace)")
                    .font(.caption.monospaced().weight(.medium))
                    .foregroundStyle(.secondary)
                Text(item.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if item.action == .resolve {
                Picker(
                    "Window",
                    selection: Binding(
                        get: { model.selectedWindows[item.id] ?? 0 },
                        set: { model.selectedWindows[item.id] = $0 }
                    )
                ) {
                    Text("Choose a window…").tag(0)
                    ForEach(plan.snapshot.windows.filter { item.windowIDs.contains($0.id) }) { window in
                        Text("\(window.title) [\(window.workspace)] · \(window.id)")
                            .tag(window.id)
                    }
                }
                .disabled(model.busy)
            }
        }
        .padding(.vertical, 10)
    }

    private var actionTitle: String {
        switch item.action {
        case .launch: "Open in \(item.assignment.workspace)"
        case .move: "Move to \(item.assignment.workspace)"
        case .alreadyPlaced: "Already in \(item.assignment.workspace)"
        case .resolve: "Choose window"
        case .safariDecision: "Review Safari"
        case .skipped: "Leave unchanged"
        case .unsupported: "Unavailable"
        }
    }
}

struct RestoreReportView: View {
    let report: RestoreReport

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Restore results", systemImage: report.allPlacementsVerified ? "checkmark.circle.fill" : "checklist")
                .font(.title2.bold())
            Text(summary)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(report.outcomes) { outcome in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(outcome.appName)
                                .font(.headline)
                            Spacer(minLength: 8)
                            Text(outcome.status.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(outcome.status.tint)
                        }
                        Text("Workspace \(outcome.workspace) · \(outcome.detail)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 9)

                    if outcome.id != report.outcomes.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.quaternary)
            }

            if !report.workspaceOutcomes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Workspace displays", systemImage: "display.2")
                        .font(.headline)
                    ForEach(report.workspaceOutcomes) { outcome in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(outcome.workspace)
                                .font(.body.monospaced().weight(.medium))
                            Text("→ \(outcome.monitorName)")
                                .font(.callout)
                            Spacer(minLength: 4)
                            Text(outcome.status.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(outcome.status.tint)
                        }
                        Text(outcome.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }

            Label(report.cleanup, systemImage: "info.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        let parts = RestoreOutcome.Status.allDisplayCases.compactMap { status -> String? in
            let total = report.outcomes.filter { $0.status == status }.count
            guard total > 0 else { return nil }
            return "\(total) \(status.summaryName)"
        }
        return parts.isEmpty ? "No app assignments were processed." : parts.joined(separator: " · ")
    }
}

private extension PlanItem.Action {
    var systemImage: String {
        switch self {
        case .launch: "arrow.up.forward.app"
        case .move: "arrow.right.square"
        case .alreadyPlaced: "checkmark.circle"
        case .resolve: "questionmark.circle"
        case .safariDecision: "safari"
        case .skipped: "forward.end"
        case .unsupported: "nosign"
        }
    }

    var tint: Color {
        switch self {
        case .launch, .move: .accentColor
        case .alreadyPlaced: .green
        case .resolve, .safariDecision: .orange
        case .skipped: .secondary
        case .unsupported: .red
        }
    }
}

private extension RestoreOutcome.Status {
    static var allDisplayCases: [Self] {
        [.completed, .skipped, .unresolved, .failed, .cancelled]
    }

    var displayName: String {
        switch self {
        case .completed: "Completed"
        case .skipped: "Unchanged"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        case .unresolved: "Needs attention"
        }
    }

    var summaryName: String {
        switch self {
        case .completed: "completed"
        case .skipped: "unchanged"
        case .cancelled: "cancelled"
        case .failed: "failed"
        case .unresolved: "need attention"
        }
    }

    var tint: Color {
        switch self {
        case .completed: .green
        case .skipped: .secondary
        case .cancelled, .unresolved: .orange
        case .failed: .red
        }
    }
}

private extension WorkspaceRestoreOutcome.Status {
    var displayName: String {
        switch self {
        case .completed: "Completed"
        case .skipped: "Unchanged"
        case .failed: "Failed"
        }
    }

    var tint: Color {
        switch self {
        case .completed: .green
        case .skipped: .secondary
        case .failed: .red
        }
    }
}
