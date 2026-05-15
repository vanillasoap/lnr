import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.linearService) var linearService
    @State private var showResetConfirm = false

    var body: some View {
        Form {
            Section("Debug") {
                if let last = appState.lastSyncDate {
                    LabeledContent("Last sync", value: last.formatted(.dateTime))
                }
                LabeledContent("Issue count", value: "\(appState.issues.count)")
                LabeledContent("Teams loaded", value: "\(appState.teams.count)")
            }
            Section {
                Button("Reset all data", role: .destructive) { showResetConfirm = true }
                    .alert("Reset all data?", isPresented: $showResetConfirm) {
                        Button("Cancel", role: .cancel) {}
                        Button("Reset", role: .destructive) { resetAll() }
                    } message: {
                        Text("This will remove your API key, preferences, and cached data. You'll need to set up lnr again.")
                    }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func resetAll() {
        KeychainService().delete()
        appState.reset()
        Task { await linearService?.stopPolling() }
    }
}
