import SwiftUI

struct FlatListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            List(appState.filteredIssues) { issue in
                IssueRowView(
                    issue: issue,
                    isExpanded: appState.expandedIssueID == issue.id,
                    isSelected: appState.selectedIssueID == issue.id,
                    onToggleExpand: { toggleExpand(issue) },
                    onOpen: { openIssue(issue) }
                )
                .id(issue.id)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .contextMenu { IssueContextMenu(issue: issue) }
                .onTapGesture { appState.selectedIssueID = issue.id }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func toggleExpand(_ issue: Issue) {
        withAnimation(.easeInOut(duration: 0.2)) {
            appState.expandedIssueID = appState.expandedIssueID == issue.id ? nil : issue.id
        }
    }

    private func openIssue(_ issue: Issue) {
        if let url = URL(string: issue.url) { NSWorkspace.shared.open(url) }
    }
}
