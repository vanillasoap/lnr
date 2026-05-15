import Testing
@testable import lnr

@MainActor
struct AppStateTests {
    @Test func initialState() {
        let state = AppState()
        #expect(state.issues.isEmpty)
        if case .notConfigured = state.connectionStatus {} else {
            Testing.Issue.record("Expected .notConfigured")
        }
        if case .idle = state.syncStatus {} else {
            Testing.Issue.record("Expected .idle")
        }
        #expect(state.viewMode == .flat)
    }

    @Test func filteredIssuesByTeam() {
        let state = AppState()
        let team1 = Team(id: "t1", key: "ENG", name: "Engineering", color: "#000")
        let team2 = Team(id: "t2", key: "DSN", name: "Design", color: "#111")
        let wfState = WorkflowState(id: "s1", name: "Todo", type: .unstarted, color: "#ccc", position: 1)
        state.issues = [
            Issue(id: "1", identifier: "ENG-1", title: "A", description: nil, priority: 1, state: wfState, team: team1, url: "", updatedAt: .now, createdAt: .now),
            Issue(id: "2", identifier: "DSN-1", title: "B", description: nil, priority: 2, state: wfState, team: team2, url: "", updatedAt: .now, createdAt: .now),
        ]
        state.selectedTeamIDs = Set(["t1"])
        #expect(state.filteredIssues.count == 1)
        #expect(state.filteredIssues.first?.identifier == "ENG-1")
    }

    @Test func searchFiltering() {
        let state = AppState()
        let team = Team(id: "t1", key: "ENG", name: "Engineering", color: "#000")
        let wfState = WorkflowState(id: "s1", name: "Todo", type: .unstarted, color: "#ccc", position: 1)
        state.issues = [
            Issue(id: "1", identifier: "ENG-1", title: "Fix login bug", description: nil, priority: 1, state: wfState, team: team, url: "", updatedAt: .now, createdAt: .now),
            Issue(id: "2", identifier: "ENG-2", title: "Add dashboard", description: nil, priority: 2, state: wfState, team: team, url: "", updatedAt: .now, createdAt: .now),
        ]
        state.selectedTeamIDs = Set(["t1"])
        state.searchText = "login"
        #expect(state.filteredIssues.count == 1)
        #expect(state.filteredIssues.first?.identifier == "ENG-1")
    }

    @Test func sortByPriority() {
        let state = AppState()
        let team = Team(id: "t1", key: "ENG", name: "Engineering", color: "#000")
        let wfState = WorkflowState(id: "s1", name: "Todo", type: .unstarted, color: "#ccc", position: 1)
        state.issues = [
            Issue(id: "1", identifier: "ENG-1", title: "Low", description: nil, priority: 4, state: wfState, team: team, url: "", updatedAt: .now, createdAt: .now),
            Issue(id: "2", identifier: "ENG-2", title: "Urgent", description: nil, priority: 1, state: wfState, team: team, url: "", updatedAt: .now, createdAt: .now),
        ]
        state.selectedTeamIDs = Set(["t1"])
        state.sortOrder = .priority
        #expect(state.filteredIssues.first?.identifier == "ENG-2")
    }
}
