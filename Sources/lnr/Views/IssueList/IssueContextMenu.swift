import SwiftUI
import AppKit

struct IssueContextMenu: View {
    let issue: Issue
    @EnvironmentObject var appState: AppState
    @Environment(\.linearService) var linearService

    var body: some View {
        Button("Open in Linear") { openInLinear() }
            .accessibilityLabel("Open issue in Linear")
        Button("Copy link") { copyToClipboard(issue.url) }
            .accessibilityLabel("Copy issue link")
        Button("Copy identifier") { copyToClipboard(issue.identifier) }
            .accessibilityLabel("Copy issue identifier")
        Divider()
        Menu("Change status...") {
            let states = appState.workflowStates[issue.team.id] ?? []
            ForEach(states) { state in
                Button {
                    changeStatus(to: state)
                } label: {
                    HStack {
                        if issue.state.id == state.id {
                            Image(systemName: "checkmark")
                        }
                        StateIcon(state: state)
                        Text(state.name)
                    }
                }
            }
        }
        .accessibilityLabel("Change issue status")
        Menu("Set priority...") {
            ForEach([(1, "Urgent"), (2, "High"), (3, "Medium"), (4, "Low"), (0, "None")], id: \.0) { value, label in
                Button {
                    changePriority(to: value)
                } label: {
                    HStack {
                        if issue.priority == value { Image(systemName: "checkmark") }
                        Text(label)
                    }
                }
            }
        }
        .accessibilityLabel("Set issue priority")
        Menu("Snooze...") {
            Button("1 hour") { snooze(hours: 1) }
            Button("4 hours") { snooze(hours: 4) }
            Button("Tomorrow") { snoozeTomorrow() }
            Button("Next week") { snoozeNextWeek() }
        }
        .accessibilityLabel("Snooze issue")
        Divider()
        Button(role: .destructive) { deleteIssue() } label: { Text("Delete") }
            .accessibilityLabel("Delete issue")
    }

    private func openInLinear() {
        let openIn = UserDefaults.standard.string(forKey: Constants.Defaults.openIssuesIn) ?? "browser"
        if openIn == "linear",
           let linearURL = URL(string: issue.url.replacingOccurrences(of: "https://linear.app", with: "linear://")) {
            if NSWorkspace.shared.urlForApplication(toOpen: linearURL) != nil {
                NSWorkspace.shared.open(linearURL)
                return
            }
        }
        if let url = URL(string: issue.url) { NSWorkspace.shared.open(url) }
    }

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func changeStatus(to state: WorkflowState) {
        let oldState = issue.state
        optimisticUpdate { $0.state = state }
        Task {
            do {
                let success = try await linearService?.updateIssueStatus(issueId: issue.id, stateId: state.id) ?? false
                if !success { revert { $0.state = oldState } }
            } catch { revert { $0.state = oldState } }
        }
    }

    private func changePriority(to priority: Int) {
        let oldPriority = issue.priority
        optimisticUpdate { $0.priority = priority }
        Task {
            do {
                let success = try await linearService?.updateIssuePriority(issueId: issue.id, priority: priority) ?? false
                if !success { revert { $0.priority = oldPriority } }
            } catch { revert { $0.priority = oldPriority } }
        }
    }

    private func snooze(hours: Int) {
        let until = Calendar.current.date(byAdding: .hour, value: hours, to: .now) ?? .now
        removeFromList()
        Task { _ = try? await linearService?.snoozeIssue(issueId: issue.id, until: until) }
    }

    private func snoozeTomorrow() {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        comps.day! += 1
        comps.hour = 9
        let until = Calendar.current.date(from: comps) ?? .now
        removeFromList()
        Task { _ = try? await linearService?.snoozeIssue(issueId: issue.id, until: until) }
    }

    private func snoozeNextWeek() {
        let until = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 9, weekday: 2), matchingPolicy: .nextTime) ?? .now
        removeFromList()
        Task { _ = try? await linearService?.snoozeIssue(issueId: issue.id, until: until) }
    }

    private func deleteIssue() {
        let alert = NSAlert()
        alert.messageText = "Delete \(issue.identifier)?"
        alert.informativeText = "This will permanently delete the issue from Linear. This action cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete")
        alert.buttons[1].hasDestructiveAction = true
        if alert.runModal() == .alertSecondButtonReturn {
            removeFromList()
            Task { _ = try? await linearService?.deleteIssue(issueId: issue.id) }
        }
    }

    private func optimisticUpdate(_ mutate: (inout Issue) -> Void) {
        if let idx = appState.issues.firstIndex(where: { $0.id == issue.id }) {
            var updated = appState.issues[idx]
            mutate(&updated)
            appState.issues[idx] = updated
        }
    }

    private func revert(_ mutate: (inout Issue) -> Void) {
        optimisticUpdate(mutate)
        appState.syncStatus = .failed(lastAttempt: .now)
    }

    private func removeFromList() {
        appState.issues.removeAll { $0.id == issue.id }
    }
}
