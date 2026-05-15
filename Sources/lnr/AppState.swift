import Foundation
import Combine

enum ConnectionStatus {
    case notConfigured
    case connecting
    case connected(userName: String, orgName: String)
    case error(message: String)
}

enum SyncStatus {
    case idle
    case syncing
    case failed(lastAttempt: Date)
}

enum ViewMode: String, CaseIterable {
    case flat
    case groupedByState
}

enum SortOrder: String, CaseIterable {
    case priority
    case status
    case updated
    case created

    var label: String {
        switch self {
        case .priority: return "Priority"
        case .status: return "Status"
        case .updated: return "Updated"
        case .created: return "Created"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var issues: [Issue] = []
    @Published var connectionStatus: ConnectionStatus = .notConfigured
    @Published var syncStatus: SyncStatus = .idle
    @Published var viewMode: ViewMode = .flat
    @Published var sortOrder: SortOrder = .updated
    @Published var searchText: String = ""
    @Published var selectedTeamIDs: Set<String> = []
    @Published var teams: [Team] = []
    @Published var workflowStates: [String: [WorkflowState]] = [:]
    @Published var lastSyncDate: Date?
    @Published var onboardingComplete: Bool = false
    @Published var expandedIssueID: String?
    @Published var selectedIssueID: String?

    @Published var pollingInterval: TimeInterval {
        didSet { UserDefaults.standard.set(pollingInterval, forKey: Constants.Defaults.pollingInterval) }
    }
    @Published var showBadgeCount: Bool {
        didSet { UserDefaults.standard.set(showBadgeCount, forKey: Constants.Defaults.showBadgeCount) }
    }

    init() {
        let stored = UserDefaults.standard.double(forKey: Constants.Defaults.pollingInterval)
        self.pollingInterval = stored > 0 ? stored : Constants.defaultPollingInterval
        self.showBadgeCount = UserDefaults.standard.object(forKey: Constants.Defaults.showBadgeCount) as? Bool ?? true
        if let modeStr = UserDefaults.standard.string(forKey: Constants.Defaults.viewMode),
           let mode = ViewMode(rawValue: modeStr) {
            self.viewMode = mode
        }
        if let sortStr = UserDefaults.standard.string(forKey: Constants.Defaults.sortOrder),
           let sort = SortOrder(rawValue: sortStr) {
            self.sortOrder = sort
        }
        if let teamIDs = UserDefaults.standard.stringArray(forKey: Constants.Defaults.selectedTeamIDs) {
            self.selectedTeamIDs = Set(teamIDs)
        }
        self.onboardingComplete = UserDefaults.standard.bool(forKey: Constants.Defaults.onboardingComplete)
    }

    var filteredIssues: [Issue] {
        var result = issues
        if !selectedTeamIDs.isEmpty {
            result = result.filter { selectedTeamIDs.contains($0.team.id) }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.identifier.lowercased().contains(query) ||
                $0.title.lowercased().contains(query)
            }
        }
        switch sortOrder {
        case .priority:
            result.sort { lhs, rhs in
                let lp = lhs.priority == 0 ? Int.max : lhs.priority
                let rp = rhs.priority == 0 ? Int.max : rhs.priority
                return lp < rp
            }
        case .status:
            result.sort { $0.state.position < $1.state.position }
        case .updated:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .created:
            result.sort { $0.createdAt > $1.createdAt }
        }
        return result
    }

    var issuesByStateGroup: [String: [Issue]] {
        Dictionary(grouping: filteredIssues) { $0.state.name }
    }

    func savePreferences() {
        UserDefaults.standard.set(viewMode.rawValue, forKey: Constants.Defaults.viewMode)
        UserDefaults.standard.set(sortOrder.rawValue, forKey: Constants.Defaults.sortOrder)
        UserDefaults.standard.set(Array(selectedTeamIDs), forKey: Constants.Defaults.selectedTeamIDs)
        UserDefaults.standard.set(onboardingComplete, forKey: Constants.Defaults.onboardingComplete)
    }

    func reset() {
        issues = []
        connectionStatus = .notConfigured
        syncStatus = .idle
        teams = []
        workflowStates = [:]
        selectedTeamIDs = []
        searchText = ""
        onboardingComplete = false
        lastSyncDate = nil
        expandedIssueID = nil
        selectedIssueID = nil
        let keys = [Constants.Defaults.pollingInterval, Constants.Defaults.viewMode,
                    Constants.Defaults.sortOrder, Constants.Defaults.selectedTeamIDs,
                    Constants.Defaults.showBadgeCount, Constants.Defaults.onboardingComplete]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}
