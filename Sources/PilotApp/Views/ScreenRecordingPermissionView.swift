import SwiftUI

struct ScreenRecordingPermissionView: View {
    let model: PilotModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Allow window previews", systemImage: "lock.rectangle")
                .font(.headline)
            Text("AeroSpace Pilot needs Screen Recording access to show images of your windows. Profiles work without it.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(model.screenRecordingPermission.hasRequested ? "Open System Settings" : "Allow Screen Recording") {
                model.enableScreenRecording()
            }
            .disabled(model.screenRecordingPermission.isRequesting || model.busy || model.captureBusy)

            if model.screenRecordingPermission.hasRequested {
                Text("In Privacy & Security → Screen Recording (or Screen & System Audio Recording), enable AeroSpace Pilot. If macOS asks, quit and reopen the app. If it is already enabled but previews remain unavailable, reopen the app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("For a rebuilt development copy, you may need to remove the old permission entry and add the current app again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Show App in Finder") {
                    model.screenRecordingPermission.showAppInFinder()
                }
            }
            if let error = model.screenRecordingPermission.settingsError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary)
        }
    }
}
