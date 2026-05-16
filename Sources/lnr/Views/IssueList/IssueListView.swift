import SwiftUI
import AppKit

struct IssueListView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.linearService) var linearService
    @State private var isSearchFocused = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            searchBar
            Divider()
            contentArea
            Divider()
            footerBar
        }
        .onKeyPress(.upArrow) { navigateIssues(direction: -1); return .handled }
        .onKeyPress(.downArrow) { navigateIssues(direction: 1); return .handled }
        .onKeyPress(.return) { openSelectedIssue(); return .handled }
        .onKeyPress(.space) { toggleSelectedExpansion(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "k")) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            isSearchFocused = true
            return .handled
        }
    }

    private var headerBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "circle.circle")
                    .font(.body.bold())
                Text("Inbox")
                    .font(.headline)
                Text("\(appState.filteredIssues.count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
            }
            Spacer()
            HStack(spacing: 12) {
                Button { Task { await linearService?.refreshNow() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 14))
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button {
                            appState.sortOrder = order
                            appState.savePreferences()
                        } label: {
                            HStack {
                                Text(order.label)
                                if appState.sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease").font(.system(size: 14))
                }

                Button {
                    appState.viewMode = appState.viewMode == .flat ? .groupedByState : .flat
                    appState.savePreferences()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 14))
                        .symbolVariant(appState.viewMode == .groupedByState ? .fill : .none)
                }
                .buttonStyle(.plain)

                Button {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                } label: {
                    Image(systemName: "gearshape").font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
            TextField("Search \(appState.filteredIssues.count) issues...", text: $appState.searchText)
                .textFieldStyle(.plain)
                .font(.body)
            if !appState.searchText.isEmpty {
                Button { appState.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            } else {
                Text("⌘K")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).stroke(.quaternary))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var contentArea: some View {
        if case .syncing = appState.syncStatus, appState.issues.isEmpty {
            LoadingView(message: "Loading issues...")
        } else if appState.filteredIssues.isEmpty {
            EmptyStateView()
        } else {
            switch appState.viewMode {
            case .flat: FlatListView()
            case .groupedByState: GroupedListView()
            }
        }
    }

    private var footerBar: some View {
        HStack {
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                    Image(systemName: "arrow.down")
                }
                .font(.caption2)
                .foregroundStyle(.quaternary)
                Text("navigate").font(.caption2).foregroundStyle(.quaternary)
                Image(systemName: "return").font(.caption2).foregroundStyle(.quaternary)
                Text("open").font(.caption2).foregroundStyle(.quaternary)
            }
            Spacer()
            Text(syncStatusLabel).font(.caption2).foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var syncStatusLabel: String {
        switch appState.syncStatus {
        case .idle:
            guard let last = appState.lastSyncDate else { return "Idle" }
            let seconds = Int(Date.now.timeIntervalSince(last))
            if seconds < 10 { return "Synced just now" }
            if seconds < 60 { return "Synced \(seconds)s ago" }
            return "Synced \(seconds / 60)m ago"
        case .syncing: return "Syncing..."
        case .failed: return "Sync failed"
        }
    }

    private func navigateIssues(direction: Int) {
        let issues = appState.filteredIssues
        guard !issues.isEmpty else { return }
        guard let currentID = appState.selectedIssueID,
              let currentIdx = issues.firstIndex(where: { $0.id == currentID }) else {
            appState.selectedIssueID = issues.first?.id
            return
        }
        let newIdx = max(0, min(issues.count - 1, currentIdx + direction))
        appState.selectedIssueID = issues[newIdx].id
    }

    private func openSelectedIssue() {
        guard let id = appState.selectedIssueID,
              let issue = appState.filteredIssues.first(where: { $0.id == id }),
              let url = URL(string: issue.url) else { return }
        NSWorkspace.shared.open(url)
    }

    private func toggleSelectedExpansion() {
        guard let id = appState.selectedIssueID else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            appState.expandedIssueID = appState.expandedIssueID == id ? nil : id
        }
    }
}
