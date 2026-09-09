import SwiftUI
import PilotProfiles

struct ProfileSidebarView: View {
    @Bindable var model: PilotModel
    @Binding var showingSave: Bool
    @State private var renameTarget: Profile?
    @State private var deleteTarget: Profile?
    @State private var renameName = ""

    var body: some View {
        List(selection: $model.selectedProfileID) {
            Section("Saved layouts") {
                ForEach(model.profiles) { profile in
                    Label(profile.name, systemImage: "rectangle.3.group")
                        .tag(profile.id)
                        .contextMenu {
                            Button("Rename…", systemImage: "pencil") {
                                beginRename(profile)
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                deleteTarget = profile
                            }
                        }
                }
            }
        }
        .navigationTitle("Profiles")
        .disabled(model.busy)
        .onChange(of: model.selectedProfileID) {
            model.selectProfile()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                VStack(spacing: 4) {
                    sidebarButton("Import Profile…", systemImage: "square.and.arrow.down") {
                        model.importProfile()
                    }
                    sidebarButton("Save Current Desktop…", systemImage: "plus.rectangle.on.rectangle") {
                        showingSave = true
                    }
                    HStack(spacing: 4) {
                        sidebarButton("Rename Selected…", systemImage: "pencil") {
                            if let profile = model.selectedProfile { beginRename(profile) }
                        }
                        .disabled(model.selectedProfile == nil)
                        sidebarButton("Delete Selected", systemImage: "trash") {
                            deleteTarget = model.selectedProfile
                        }
                        .disabled(!model.canDeleteSelectedProfile)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(.bar)
        }
        .alert("Rename Saved Layout", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Layout name", text: $renameName)
            Button("Save") {
                if let profile = renameTarget {
                    model.renameProfile(profile, name: renameName)
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            Text("Choose a name up to 200 characters.")
        }
        .confirmationDialog(
            "Delete saved layout?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let profile = deleteTarget {
                    model.deleteProfile(profile)
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text(deleteTarget.map { "Delete \($0.name)? This cannot be undone." } ?? "")
        }
    }

    private func sidebarButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func beginRename(_ profile: Profile) {
        renameName = profile.name
        renameTarget = profile
    }

}
