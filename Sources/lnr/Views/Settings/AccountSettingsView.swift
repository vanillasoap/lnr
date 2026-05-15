import SwiftUI

struct AccountSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.linearService) var linearService
    @State private var isReplacing = false
    @State private var newKey = ""
    @State private var isValidating = false

    var body: some View {
        Form {
            Section("API Key") {
                if isReplacing {
                    HStack {
                        SecureField("lin_api_...", text: $newKey).textFieldStyle(.roundedBorder)
                        Button("Save") { replaceKey() }.disabled(newKey.count < 10 || isValidating)
                        Button("Cancel") { isReplacing = false; newKey = "" }
                    }
                } else {
                    HStack {
                        Text(maskedKey).font(.body.monospaced())
                        Spacer()
                        Button("Replace...") { isReplacing = true }
                    }
                }
            }
            if case .connected(let name, let org) = appState.connectionStatus {
                Section("Account") {
                    LabeledContent("Connected as", value: "\(name) · \(org)")
                }
            }
            Section("Teams") {
                ForEach(appState.teams) { team in
                    Toggle(isOn: Binding(
                        get: { appState.selectedTeamIDs.contains(team.id) },
                        set: { on in
                            if on { appState.selectedTeamIDs.insert(team.id) }
                            else { appState.selectedTeamIDs.remove(team.id) }
                            appState.savePreferences()
                        }
                    )) {
                        HStack {
                            Circle().fill(Color(hex: team.color)).frame(width: 8, height: 8)
                            Text(team.key).font(.caption.monospaced().bold())
                            Text(team.name)
                        }
                    }
                }
            }
            Section {
                Button("Sign out", role: .destructive) { signOut() }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var maskedKey: String {
        guard let key = try? KeychainService().load() else { return "No key" }
        return String(key.prefix(8)) + String(repeating: "•", count: 20)
    }

    private func replaceKey() {
        isValidating = true
        Task {
            do {
                let viewer = try await linearService?.validateAPIKey(newKey)
                if let viewer {
                    try KeychainService().save(newKey)
                    appState.connectionStatus = .connected(userName: viewer.name, orgName: viewer.orgName)
                    isReplacing = false
                    newKey = ""
                }
            } catch {}
            isValidating = false
        }
    }

    private func signOut() {
        KeychainService().delete()
        appState.reset()
        Task { await linearService?.stopPolling() }
    }
}
