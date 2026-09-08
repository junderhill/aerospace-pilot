import AppKit
import SwiftUI
import PilotCore
import PilotOverview

struct WindowPreviewsView: View {
    @Bindable var model: PilotModel

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                    Text("Capture images of current windows without switching workspaces.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button(
                            model.captureBusy ? "Capturing…" : "Capture Window Previews",
                            systemImage: "camera.viewfinder"
                        ) {
                            Task { await model.capturePreviews() }
                        }
                        .disabled(model.captureBusy || model.busy || !model.screenRecordingPermission.isGranted)

                        if model.captureBusy {
                            ProgressView()
                                .controlSize(.small)
                        }

                        if let duration = model.captureDuration, !model.thumbnails.isEmpty {
                            Text("\(model.thumbnails.count) updated in \(duration.formatted(.number.precision(.fractionLength(2)))) seconds")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !model.thumbnails.isEmpty {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 210, maximum: 340), spacing: 12)],
                            alignment: .leading,
                            spacing: 12
                        ) {
                            ForEach(model.thumbnails, id: \.windowID) { thumbnail in
                                WindowPreviewCard(
                                    thumbnail: thumbnail,
                                    window: model.previewWindowsByID[thumbnail.windowID]
                                )
                            }
                        }
                    }
            }
            .padding(.top, 10)
        } label: {
            Label("Window previews", systemImage: "rectangle.stack")
                .font(.headline)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary)
        }
    }
}

private struct WindowPreviewCard: View {
    let thumbnail: Thumbnail
    let window: DesktopWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Group {
                if let data = thumbnail.png, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "rectangle.slash")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 125)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            .clipped()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(window?.appName ?? "Window \(thumbnail.windowID)")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let workspace = window?.workspace {
                    Text(workspace)
                        .font(.caption.monospaced().weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        .accessibilityLabel("Workspace \(workspace)")
                }
            }

            if let title = window?.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(thumbnail.label)
                .font(.caption)
                .foregroundStyle(thumbnail.state == .unavailable ? .orange : .secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(.quaternary)
        }
    }
}
