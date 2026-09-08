import SwiftUI
import PilotCore
import PilotProfiles

struct SafariDecisionView: View {
    @Bindable var model: PilotModel
    @State private var choice: SafariChoice = .leaveInPlace

    private var destination: String {
        model.plan?.items.first { $0.assignment.bundleID == Protection.safari }?.assignment.workspace ?? "the saved workspace"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Existing Safari windows").font(.title2.bold())
                Text("Choose what happens to all existing Safari windows and tabs, including those in other workspaces.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Safari windows", selection: $choice) {
                Text("Move all existing windows to \(destination)").tag(SafariChoice.moveAll)
                Text("Leave all windows and tabs where they are").tag(SafariChoice.leaveInPlace)
                Text("Close all existing windows and tabs").tag(SafariChoice.closeAll)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if choice == .closeAll {
                Label("All existing Safari windows will close. Any Safari confirmation must be answered before restoration can continue.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Nothing changes until you apply the preview. Cancel returns to the preview without restoring any apps.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel", role: .cancel) { model.cancelSafariDecision() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(role: choice == .closeAll ? .destructive : nil) {
                    model.confirmSafariDecision(choice)
                } label: {
                    Text(choice == .closeAll ? "Close Safari Windows & Apply" : "Apply \(model.plan?.profile.name ?? "Profile")")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}
