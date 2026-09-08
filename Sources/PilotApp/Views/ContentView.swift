import SwiftUI

struct ContentView: View {
    @Bindable var model: PilotModel
    @State private var saveName = "Desktop"
    @State private var showingSave = false

    var body: some View {
        NavigationSplitView {
            ProfileSidebarView(model: model, showingSave: $showingSave)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            ProfileDetailView(model: model)
        }
        .navigationSplitViewStyle(.balanced)
        .alert("Save current desktop", isPresented: $showingSave) {
            TextField("Profile name", text: $saveName)
            Button("Save") {
                Task { await model.saveDesktop(name: saveName) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save app identities and workspace assignments. ChatGPT is excluded, and windows with the same app need distinct titles.")
        }
        .sheet(isPresented: $model.showingSafariDecision) {
            SafariDecisionView(model: model)
        }
    }
}
