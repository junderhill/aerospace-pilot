import AppKit
import SwiftUI
import PilotCore
import PilotOverview

struct WorkspaceOverviewView: View {
    let controller: WorkspaceOverviewController
    @Bindable var model: WorkspaceOverviewModel
    @FocusState private var searchFocused: Bool

    init(controller: WorkspaceOverviewController) {
        self.controller = controller
        self.model = controller.model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            TextField("Find a workspace, app, or window…", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused($searchFocused)
                .onSubmit {
                    if let selected = model.selectedWorkspace { controller.activate(workspace: selected) }
                }
                .onKeyPress(.downArrow) { model.moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { model.moveSelection(-1); return .handled }
                .onChange(of: model.query) { _, _ in
                    model.selectedWorkspace = nil
                    model.reconcileSelection()
                }

            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.canCapture && !model.loading {
                HStack {
                    Text("Window names are available. Allow Screen Recording to show images.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Allow Previews…") { controller.enablePreviews() }
                }
            }

            ScrollViewReader { scroll in
                ScrollView {
                    if model.groups.isEmpty {
                        ContentUnavailableView(
                            model.loading ? "Loading workspaces…" : "No matching workspaces",
                            systemImage: "rectangle.3.group",
                            description: Text(model.loading ? "Reading the current AeroSpace layout." : "Try another search or refresh the overview.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 310, maximum: 520), spacing: 20)], alignment: .leading, spacing: 20) {
                            ForEach(model.groups) { group in
                                OverviewWorkspaceCard(group: group, controller: controller)
                                    .id(group.name)
                            }
                        }
                        .padding(3)
                    }
                }
                .onChange(of: model.selectedWorkspace) { _, name in
                    if let name { withAnimation(.easeOut(duration: 0.15)) { scroll.scrollTo(name) } }
                }
            }

            HStack {
                Text("↑ ↓ Select workspace · Return Switch · Click a window to focus it · Esc Close")
                Spacer()
                if model.capturing {
                    ProgressView().controlSize(.small)
                    Text("Loading previews…")
                } else {
                    Text("\(model.groups.count) \(model.groups.count == 1 ? "workspace" : "workspaces")")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .task {
            // The panel must become key before assigning SwiftUI's text focus.
            await Task.yield()
            searchFocused = true
        }
        .onExitCommand { controller.dismiss() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspaces").font(.largeTitle.bold())
                Text("All AeroSpace workspaces · \(OverviewShortcut.label)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh", systemImage: "arrow.clockwise") { controller.refresh() }
                .disabled(model.loading || model.navigating)
            Button("Close", systemImage: "xmark") { controller.dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }
}

private struct OverviewWorkspaceCard: View {
    let group: OverviewWorkspace
    let controller: WorkspaceOverviewController
    private var selected: Bool { controller.model.selectedWorkspace == group.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                controller.activate(workspace: group.name)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Text(group.name)
                        .font(.title.bold().monospaced())
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(group.windows.count) \(group.windows.count == 1 ? "window" : "windows")")
                        Text(group.monitorName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if group.isVisible {
                        Text("Visible")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Switch to workspace \(group.name)")
            .accessibilityLabel("Switch to workspace \(group.name), \(group.windows.count) windows")

            if group.windows.isEmpty {
                Text("Empty workspace")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
                        ForEach(group.windows) { window in
                            OverviewWindowTile(window: window, thumbnail: controller.model.thumbnails[window.id], loading: controller.model.capturing) {
                                controller.activate(workspace: group.name, window: window)
                            }
                        }
                    }
                    .padding(2)
                }
                .frame(height: group.windows.count <= 2 ? 175 : 340)
            }
        }
        .disabled(controller.model.navigating)
        .padding(16)
        .background(.background.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 3 : 1)
        }
    }
}

private struct OverviewWindowTile: View {
    let window: DesktopWindow
    let thumbnail: Thumbnail?
    let loading: Bool
    let activate: () -> Void

    var body: some View {
        Button(action: activate) {
            VStack(alignment: .leading, spacing: 5) {
                Group {
                    if let data = thumbnail?.png, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "macwindow").font(.title2)
                            Text(loading && thumbnail == nil ? "Loading…" : "No preview")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 105)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                Text(window.appName).font(.callout.weight(.semibold)).lineLimit(1)
                Text(window.title.isEmpty ? "Untitled window" : window.title)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if thumbnail?.state == .cached {
                    Text(thumbnail?.label ?? "Cached").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(thumbnail?.reason ?? "Focus \(window.appName): \(window.title)")
        .accessibilityLabel("\(window.appName), \(window.title), workspace \(window.workspace)")
    }
}
