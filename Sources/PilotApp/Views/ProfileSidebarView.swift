import SwiftUI

struct ProfileSidebarView: View {
    @Bindable var model: PilotModel
    @Binding var showingSave: Bool

    var body: some View {
        List(selection: $model.selectedProfileID) {
            Section("Saved layouts") {
                ForEach(model.profiles) { profile in
                    Label(profile.name, systemImage: "rectangle.3.group")
                        .tag(profile.id)
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
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(.bar)
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
}
