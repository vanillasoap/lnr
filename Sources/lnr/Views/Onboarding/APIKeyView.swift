import SwiftUI

struct APIKeyView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    @EnvironmentObject var appState: AppState
    @Environment(\.linearService) var linearService

    @State private var apiKey: String = ""
    @State private var isValidating = false
    @State private var validationResult: ValidationResult?

    enum ValidationResult {
        case success(userName: String, orgName: String)
        case failure(message: String)
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chevron.down")
                .foregroundStyle(.tertiary)
                .padding(.top, 12)

            Text("Connect to Linear")
                .font(.title3.bold())

            Text("Paste a personal API key from linear.app/settings/api.\nIt's stored securely in your macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("Personal API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    SecureField("lin_api_...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiKey) { _, newValue in
                            if newValue.hasPrefix("lin_api_") && newValue.count > 20 {
                                validate()
                            } else {
                                validationResult = nil
                            }
                        }

                    if isValidating {
                        ProgressView()
                            .controlSize(.small)
                    } else if case .success = validationResult {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(.horizontal, 24)

            if let result = validationResult {
                switch result {
                case .success(let userName, let orgName):
                    Label("Connected as \(userName) · \(orgName)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                case .failure(let message):
                    Label(message, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                Text("Key never leaves your machine. lnr talks to Linear directly via HTTPS.")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 24)

            HStack {
                Button("Skip") { onSkip() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Continue") { saveAndContinue() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    private var isValid: Bool {
        if case .success = validationResult { return true }
        return false
    }

    private func validate() {
        isValidating = true
        validationResult = nil
        Task {
            do {
                let viewer = try await linearService?.validateAPIKey(apiKey)
                if let viewer {
                    validationResult = .success(userName: viewer.name, orgName: viewer.orgName)
                }
            } catch {
                validationResult = .failure(message: "Invalid API key. Check and try again.")
            }
            isValidating = false
        }
    }

    private func saveAndContinue() {
        let keychain = KeychainService()
        try? keychain.save(apiKey)
        if case .success(let name, let org) = validationResult {
            appState.connectionStatus = .connected(userName: name, orgName: org)
            Task {
                let teamsWithCounts = try await linearService?.fetchTeams() ?? []
                appState.teams = teamsWithCounts.map(\.team)
                appState.selectedTeamIDs = Set(teamsWithCounts.filter { $0.issueCount > 0 }.map(\.team.id))
            }
        }
        onContinue()
    }
}
