import SwiftUI

enum StateTab: String, CaseIterable {
    case active = "Active"
    case backlog = "Backlog"
    case done = "Done"

    var stateTypes: [StateType] {
        switch self {
        case .active: return [.started, .unstarted]
        case .backlog: return [.backlog]
        case .done: return [.completed, .cancelled]
        }
    }
}

struct GroupedListView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: StateTab = .active
    @State private var collapsedSections: Set<String> = []
    @State private var teamFilter: String?

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            groupedList
            groupedFooter
        }
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(StateTab.allCases, id: \.self) { tab in
                Button(tab.rawValue) { selectedTab = tab }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                    .buttonStyle(.plain)
            }
            Spacer()
            Menu {
                Button("All teams") { teamFilter = nil }
                Divider()
                ForEach(appState.teams.filter { appState.selectedTeamIDs.contains($0.id) }) { team in
                    Button(team.name) { teamFilter = team.id }
                }
            } label: {
                Text(teamFilter == nil ? "All teams" : appState.teams.first { $0.id == teamFilter }?.name ?? "All teams")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var filteredByTab: [Issue] {
        appState.filteredIssues
            .filter { selectedTab.stateTypes.contains($0.state.type) }
            .filter { teamFilter == nil || $0.team.id == teamFilter }
    }

    private var groupedIssues: [(name: String, color: String, issues: [Issue])] {
        let grouped = Dictionary(grouping: filteredByTab) { $0.state.name }
        return grouped.map { (name: $0.key, color: $0.value.first?.state.color ?? "#888", issues: $0.value) }
            .sorted { ($0.issues.first?.state.position ?? 0) < ($1.issues.first?.state.position ?? 0) }
    }

    private var groupedList: some View {
        List {
            ForEach(groupedIssues, id: \.name) { group in
                Section {
                    if !collapsedSections.contains(group.name) {
                        ForEach(group.issues) { issue in
                            IssueRowView(
                                issue: issue,
                                isExpanded: appState.expandedIssueID == issue.id,
                                isSelected: appState.selectedIssueID == issue.id,
                                onToggleExpand: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        appState.expandedIssueID = appState.expandedIssueID == issue.id ? nil : issue.id
                                    }
                                },
                                onOpen: {
                                    if let url = URL(string: issue.url) { NSWorkspace.shared.open(url) }
                                }
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .contextMenu { IssueContextMenu(issue: issue) }
                            .onTapGesture { appState.selectedIssueID = issue.id }
                        }
                    }
                } header: {
                    Button {
                        if collapsedSections.contains(group.name) {
                            collapsedSections.remove(group.name)
                        } else {
                            collapsedSections.insert(group.name)
                        }
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: group.color))
                                .frame(width: 8, height: 8)
                            Text(group.name.uppercased())
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Text("\(group.issues.count)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Image(systemName: collapsedSections.contains(group.name) ? "chevron.right" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var groupedFooter: some View {
        let active = appState.filteredIssues.filter { [.started, .unstarted].contains($0.state.type) }.count
        let todo = appState.filteredIssues.filter { $0.state.type == .unstarted }.count
        let review = appState.filteredIssues.filter { $0.state.name.lowercased().contains("review") }.count
        return HStack {
            Text("\(active) active · \(todo) todo · \(review) review")
                .font(.caption2)
                .foregroundStyle(.quaternary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
