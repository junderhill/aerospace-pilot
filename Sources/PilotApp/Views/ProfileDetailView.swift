import SwiftUI
import PilotProfiles

struct ProfileDetailView: View {
    @Bindable var model: PilotModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ConnectionStatusView(health: model.health)

                if let profile = model.selectedProfile {
                    ProfileOverviewView(model: model, profile: profile)

                    if let message = model.message {
                        FeedbackBanner(
                            message: message,
                            isError: model.messageIsError,
                            dismiss: model.dismissMessage
                        )
                    }

                    if let plan = model.plan {
                        RestorePreviewView(model: model, plan: plan)
                    }

                    if let report = model.report {
                        RestoreReportView(report: report)
                    }

                    WindowPreviewsView(model: model)
                } else {
                    ContentUnavailableView(
                        "Select a profile",
                        systemImage: "rectangle.3.group",
                        description: Text("Choose a saved layout from the sidebar.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("AeroSpace Pilot")
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await model.refreshHealth() }
            }
            .disabled(model.busy)
        }
    }
}

private struct ProfileOverviewView: View {
    @Bindable var model: PilotModel
    let profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(profile.name)
                    .font(.largeTitle.bold())
                Text("Restore app windows to their saved workspaces.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(model.plan == nil ? "Preview Restore" : "Refresh Preview", systemImage: "eye") {
                    Task { await model.preview() }
                }
                .keyboardShortcut("r")
                .disabled(model.busy || model.health?.canRestore != true)

                Button("Export…", systemImage: "square.and.arrow.up") {
                    model.exportProfile()
                }
                .disabled(!model.canExport)

                if model.plan != nil {
                    Button("Apply \(profile.name)", systemImage: "play.fill") {
                        model.beginApply()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || model.health?.canRestore != true)
                }
            }

            if model.busy {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.isRestoring ? "Restoring \(profile.name)…" : "Preparing…")
                        .foregroundStyle(.secondary)
                    if model.isRestoring {
                        Button("Cancel Restore") {
                            model.cancelRestore()
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Saved layout · \(profile.assignments.count) apps", systemImage: "rectangle.grid.1x2")
                    .font(.headline)

                VStack(spacing: 0) {
                    ForEach(profile.assignments) { assignment in
                        AssignmentRow(assignment: assignment)
                        if assignment.id != profile.assignments.last?.id {
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
            }

            Label("ChatGPT is protected and stays where it is.", systemImage: "shield.checkered")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AssignmentRow: View {
    let assignment: Assignment

    var body: some View {
        HStack(spacing: 12) {
            Text(assignment.workspace)
                .font(.callout.monospaced().weight(.semibold))
                .frame(width: 34, height: 28)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Workspace \(assignment.workspace)")

            Image(systemName: appIcon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(assignment.appName)
                    .font(.body.weight(.medium))
                Text(assignment.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private var appIcon: String {
        switch assignment.appName.lowercased() {
        case "safari": "safari"
        case "visual studio code": "chevron.left.forwardslash.chevron.right"
        case "calendar": "calendar"
        default: "app"
        }
    }
}

private struct FeedbackBanner: View {
    let message: String
    let isError: Bool
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(message)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
        }
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(tint.opacity(0.2))
        }
    }

    private var tint: Color { isError ? .red : .green }
}
