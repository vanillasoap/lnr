import SwiftUI

struct TeamPickerView: View {
    let onFinish: () -> Void
    let onBack: () -> Void

    @EnvironmentObject var appState: AppState
    @Environment(\.linearService) var linearService

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chevron.down")
                .foregroundStyle(.tertiary)
                .padding(.top, 12)

            Text("Pick teams")
                .font(.title3.bold())

            Text("Show issues from these teams in your menubar.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                ForEach(appState.teams) { team in
                    TeamRow(
                        team: team,
                        issueCount: appState.issues.filter { $0.team.id == team.id }.count,
                        isSelected: appState.selectedTeamIDs.contains(team.id),
                        onToggle: {
                            if appState.selectedTeamIDs.contains(team.id) {
                                appState.selectedTeamIDs.remove(team.id)
                            } else {
                                appState.selectedTeamIDs.insert(team.id)
                            }
                        }
                    )
                }
            }
            .listStyle(.plain)

            HStack {
                Button("Back") { onBack() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Finish") { finish() }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.selectedTeamIDs.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    private func finish() {
        appState.savePreferences()
        Task {
            for teamId in appState.selectedTeamIDs {
                let states = try await linearService?.fetchWorkflowStates(teamId: teamId) ?? []
                appState.workflowStates[teamId] = states.sorted { $0.position < $1.position }
            }
            await linearService?.startPolling()
        }
        onFinish()
    }
}

struct TeamRow: View {
    let team: Team
    let issueCount: Int
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? .blue : .secondary)

                Circle()
                    .fill(Color(hex: team.color))
                    .frame(width: 8, height: 8)

                Text(team.key)
                    .font(.caption.monospaced().bold())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(.quaternary))

                Text(team.name)
                    .font(.body)

                Spacer()

                Text("\(issueCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
