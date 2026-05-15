# lnr Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menubar app that shows Linear issues assigned to the current user, with actions to triage them without leaving the workflow.

**Architecture:** AppKit shell (NSStatusItem + NSPopover) hosting SwiftUI views. LinearService actor handles all GraphQL API communication with polling. AppState ObservableObject is the single source of truth shared across views.

**Tech Stack:** Swift, SwiftUI, AppKit, macOS 14+, URLSession, Security framework, SMAppService. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-05-15-lnr-design.md`

---

## File Map

| File | Responsibility |
|---|---|
| `lnr/lnrApp.swift` | @main App, NSApplicationDelegateAdaptor, no WindowGroup |
| `lnr/AppDelegate.swift` | NSStatusItem, NSPopover, icon state updates via Combine |
| `lnr/AppState.swift` | ObservableObject: issues, connectionStatus, syncStatus, viewMode, sort, filter, teams |
| `lnr/Models/Issue.swift` | Issue model (Codable, Identifiable) |
| `lnr/Models/WorkflowState.swift` | WorkflowState model + StateType enum |
| `lnr/Models/Team.swift` | Team model |
| `lnr/Services/KeychainService.swift` | Save/load/delete API key from macOS Keychain |
| `lnr/Services/LinearService.swift` | GraphQL client, polling loop, all queries and mutations |
| `lnr/Views/PopoverContentView.swift` | Root view — switches between onboarding and issue list |
| `lnr/Views/Onboarding/WelcomeView.swift` | Step 1: welcome screen |
| `lnr/Views/Onboarding/APIKeyView.swift` | Step 2: API key input + validation |
| `lnr/Views/Onboarding/TeamPickerView.swift` | Step 3: team selection |
| `lnr/Views/IssueList/IssueListView.swift` | Header, search, footer, hosts flat/grouped |
| `lnr/Views/IssueList/FlatListView.swift` | View A — sorted flat list |
| `lnr/Views/IssueList/GroupedListView.swift` | View B — grouped by state with tabs |
| `lnr/Views/IssueList/IssueRowView.swift` | Compact + expanded row states |
| `lnr/Views/IssueList/EmptyStateView.swift` | Inbox zero, loading, error states |
| `lnr/Views/Settings/SettingsWindowController.swift` | NSWindow hosting SwiftUI settings |
| `lnr/Views/Settings/GeneralSettingsView.swift` | Refresh interval, launch at login, appearance |
| `lnr/Views/Settings/AccountSettingsView.swift` | API key, teams, sign out |
| `lnr/Views/Settings/ShortcutsSettingsView.swift` | Keyboard shortcut reference |
| `lnr/Views/Settings/AdvancedSettingsView.swift` | Reset, debug info |
| `lnr/Utilities/Constants.swift` | Dimensions, API URL, UserDefaults keys |
| `lnrTests/KeychainServiceTests.swift` | Keychain CRUD tests |
| `lnrTests/LinearServiceTests.swift` | GraphQL request building, response parsing |
| `lnrTests/AppStateTests.swift` | State transitions, filtering, sorting |

---

## Task 1: Xcode Project Scaffold

**Files:**
- Create: Xcode project `lnr` with target `lnr` and test target `lnrTests`
- Create: `lnr/Utilities/Constants.swift`
- Create: `lnr/lnrApp.swift`

- [ ] **Step 1: Create Xcode project**

Open Xcode → File → New → Project → macOS → App.
- Product Name: `lnr`
- Team: None (unsigned for now)
- Organization Identifier: `com.lnr`
- Interface: SwiftUI
- Language: Swift
- Testing System: Swift Testing
- Uncheck "Include Tests" (we'll add manually for control)
- Set deployment target: macOS 14.0

Alternatively, from the command line, create the directory structure:

```bash
mkdir -p lnr/lnr/{Models,Services,Views/{Onboarding,IssueList,Settings},Utilities}
mkdir -p lnr/lnrTests
```

- [ ] **Step 2: Create Constants.swift**

```swift
// lnr/Utilities/Constants.swift
import Foundation

enum Constants {
    static let popoverWidth: CGFloat = 360
    static let popoverMaxHeight: CGFloat = 500
    static let settingsWidth: CGFloat = 480
    static let settingsHeight: CGFloat = 400
    static let linearAPIURL = URL(string: "https://api.linear.app/graphql")!
    static let defaultPollingInterval: TimeInterval = 60

    enum Defaults {
        static let pollingInterval = "pollingInterval"
        static let viewMode = "viewMode"
        static let sortOrder = "sortOrder"
        static let selectedTeamIDs = "selectedTeamIDs"
        static let showBadgeCount = "showBadgeCount"
        static let appearanceMode = "appearanceMode"
        static let openIssuesIn = "openIssuesIn"
        static let onboardingComplete = "onboardingComplete"
    }
}
```

- [ ] **Step 3: Replace lnrApp.swift with bare shell**

```swift
// lnr/lnrApp.swift
import SwiftUI

@main
struct lnrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

This won't compile yet — `AppDelegate` doesn't exist. That's Task 2.

- [ ] **Step 4: Commit**

```bash
git add lnr/
git commit -m "scaffold: Xcode project with constants and app entry point"
```

---

## Task 2: Models

**Files:**
- Create: `lnr/Models/WorkflowState.swift`
- Create: `lnr/Models/Team.swift`
- Create: `lnr/Models/Issue.swift`

- [ ] **Step 1: Create WorkflowState.swift**

```swift
// lnr/Models/WorkflowState.swift
import Foundation

enum StateType: String, Codable, CaseIterable {
    case backlog
    case unstarted
    case started
    case completed
    case cancelled
}

struct WorkflowState: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: StateType
    let color: String
    let position: Double
}
```

- [ ] **Step 2: Create Team.swift**

```swift
// lnr/Models/Team.swift
import Foundation

struct Team: Codable, Identifiable, Hashable {
    let id: String
    let key: String
    let name: String
    let color: String
}
```

- [ ] **Step 3: Create Issue.swift**

```swift
// lnr/Models/Issue.swift
import Foundation

struct Issue: Codable, Identifiable {
    let id: String
    let identifier: String
    let title: String
    let description: String?
    var priority: Int
    var state: WorkflowState
    let team: Team
    let url: String
    let updatedAt: Date
    let createdAt: Date

    var priorityLabel: String {
        switch priority {
        case 1: return "Urgent"
        case 2: return "High"
        case 3: return "Medium"
        case 4: return "Low"
        default: return "None"
        }
    }

    var priorityIconName: String {
        switch priority {
        case 1: return "exclamationmark.triangle.fill"
        case 2: return "chart.bar.fill"
        case 3: return "chart.bar.fill"
        case 4: return "chart.bar.fill"
        default: return "circle"
        }
    }

    var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: .now)
    }

    var strippedDescription: String? {
        guard let description else { return nil }
        return description
            .replacingOccurrences(of: #"[#*_~`>\[\]()!]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add lnr/Models/
git commit -m "feat: add Issue, WorkflowState, and Team models"
```

---

## Task 3: KeychainService

**Files:**
- Create: `lnr/Services/KeychainService.swift`
- Create: `lnrTests/KeychainServiceTests.swift`

- [ ] **Step 1: Write KeychainService tests**

```swift
// lnrTests/KeychainServiceTests.swift
import Testing
@testable import lnr

struct KeychainServiceTests {
    let service = KeychainService(service: "com.lnr.tests")

    init() {
        service.delete()
    }

    @Test func saveAndLoad() throws {
        try service.save("lin_api_test123")
        let loaded = try service.load()
        #expect(loaded == "lin_api_test123")
    }

    @Test func loadWhenEmpty() {
        let loaded = try? service.load()
        #expect(loaded == nil)
    }

    @Test func deleteRemovesKey() throws {
        try service.save("lin_api_test123")
        service.delete()
        let loaded = try? service.load()
        #expect(loaded == nil)
    }

    @Test func saveOverwrites() throws {
        try service.save("lin_api_first")
        try service.save("lin_api_second")
        let loaded = try service.load()
        #expect(loaded == "lin_api_second")
    }
}
```

- [ ] **Step 2: Run tests — expect failure**

```bash
xcodebuild test -scheme lnr -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: compilation error — `KeychainService` doesn't exist.

- [ ] **Step 3: Implement KeychainService**

```swift
// lnr/Services/KeychainService.swift
import Foundation
import Security

struct KeychainService {
    let service: String

    init(service: String = "com.lnr.api-key") {
        self.service = service
    }

    func save(_ value: String) throws {
        let data = Data(value.utf8)
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "linear-api-key",
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "linear-api-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound { return nil }
            throw KeychainError.loadFailed(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "linear-api-key"
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
xcodebuild test -scheme lnr -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lnr/Services/KeychainService.swift lnrTests/KeychainServiceTests.swift
git commit -m "feat: add KeychainService with tests"
```

---

## Task 4: AppState

**Files:**
- Create: `lnr/AppState.swift`
- Create: `lnrTests/AppStateTests.swift`

- [ ] **Step 1: Write AppState tests**

```swift
// lnrTests/AppStateTests.swift
import Testing
@testable import lnr

@MainActor
struct AppStateTests {
    @Test func initialState() {
        let state = AppState()
        #expect(state.issues.isEmpty)
        if case .notConfigured = state.connectionStatus {} else {
            Issue.record("Expected .notConfigured")
        }
        if case .idle = state.syncStatus {} else {
            Issue.record("Expected .idle")
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
```

- [ ] **Step 2: Run tests — expect failure**

Expected: compilation error — `AppState` doesn't exist.

- [ ] **Step 3: Implement AppState**

```swift
// lnr/AppState.swift
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
```

- [ ] **Step 4: Run tests — expect pass**

```bash
xcodebuild test -scheme lnr -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lnr/AppState.swift lnrTests/AppStateTests.swift
git commit -m "feat: add AppState with filtering, sorting, and persistence"
```

---

## Task 5: LinearService — GraphQL Client & Parsing

**Files:**
- Create: `lnr/Services/LinearService.swift`
- Create: `lnrTests/LinearServiceTests.swift`

- [ ] **Step 1: Write response parsing tests**

```swift
// lnrTests/LinearServiceTests.swift
import Testing
import Foundation
@testable import lnr

struct LinearServiceTests {
    @Test func parseViewerResponse() throws {
        let json = """
        {"data":{"viewer":{"id":"user1","name":"Sam Greene","organization":{"name":"Acme"}}}}
        """.data(using: .utf8)!
        let viewer = try LinearService.parseViewerResponse(json)
        #expect(viewer.name == "Sam Greene")
        #expect(viewer.orgName == "Acme")
    }

    @Test func parseIssuesResponse() throws {
        let json = """
        {"data":{"viewer":{"assignedIssues":{"nodes":[
            {"id":"i1","identifier":"ENG-1","title":"Fix bug","description":"Details","priority":1,
             "state":{"id":"s1","name":"In Progress","type":"started","color":"#f59e0b","position":1.0},
             "team":{"id":"t1","key":"ENG","name":"Engineering","color":"#000"},
             "url":"https://linear.app/acme/issue/ENG-1","updatedAt":"2026-05-15T10:00:00.000Z","createdAt":"2026-05-14T08:00:00.000Z"}
        ]}}}}
        """.data(using: .utf8)!
        let issues = try LinearService.parseIssuesResponse(json)
        #expect(issues.count == 1)
        #expect(issues[0].identifier == "ENG-1")
        #expect(issues[0].priority == 1)
        #expect(issues[0].state.type == .started)
    }

    @Test func parseTeamsResponse() throws {
        let json = """
        {"data":{"teams":{"nodes":[
            {"id":"t1","key":"ENG","name":"Engineering","color":"#000","issues":{"nodes":[{"id":"i1"},{"id":"i2"}]}}
        ]}}}
        """.data(using: .utf8)!
        let teams = try LinearService.parseTeamsResponse(json)
        #expect(teams.count == 1)
        #expect(teams[0].team.key == "ENG")
        #expect(teams[0].issueCount == 2)
    }

    @Test func parseWorkflowStatesResponse() throws {
        let json = """
        {"data":{"team":{"states":{"nodes":[
            {"id":"s1","name":"Backlog","type":"backlog","color":"#ccc","position":0.0},
            {"id":"s2","name":"Todo","type":"unstarted","color":"#aaa","position":1.0}
        ]}}}}
        """.data(using: .utf8)!
        let states = try LinearService.parseWorkflowStatesResponse(json)
        #expect(states.count == 2)
        #expect(states[0].name == "Backlog")
    }

    @Test func buildGraphQLRequest() throws {
        let request = try LinearService.buildRequest(
            query: "{ viewer { id } }",
            variables: nil,
            apiKey: "lin_api_test"
        )
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "lin_api_test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }
}
```

- [ ] **Step 2: Run tests — expect failure**

Expected: compilation error — `LinearService` doesn't exist.

- [ ] **Step 3: Implement LinearService**

```swift
// lnr/Services/LinearService.swift
import Foundation

struct ViewerInfo {
    let id: String
    let name: String
    let orgName: String
}

struct TeamWithCount {
    let team: Team
    let issueCount: Int
}

actor LinearService {
    private let appState: AppState
    private let keychainService: KeychainService
    private var pollingTask: Task<Void, Never>?

    init(appState: AppState, keychainService: KeychainService = KeychainService()) {
        self.appState = appState
        self.keychainService = keychainService
    }

    // MARK: - Request Building

    static func buildRequest(query: String, variables: [String: Any]? = nil, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: Constants.linearAPIURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["query": query]
        if let variables { body["variables"] = variables }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Response Parsing

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: str) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(str)")
        }
        return d
    }()

    static func parseViewerResponse(_ data: Data) throws -> ViewerInfo {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let dataObj = json?["data"] as? [String: Any],
              let viewer = dataObj["viewer"] as? [String: Any],
              let id = viewer["id"] as? String,
              let name = viewer["name"] as? String,
              let org = viewer["organization"] as? [String: Any],
              let orgName = org["name"] as? String
        else { throw LinearError.invalidResponse }
        return ViewerInfo(id: id, name: name, orgName: orgName)
    }

    static func parseIssuesResponse(_ data: Data) throws -> [Issue] {
        struct Response: Decodable {
            let data: DataWrapper
            struct DataWrapper: Decodable { let viewer: Viewer }
            struct Viewer: Decodable { let assignedIssues: Nodes }
            struct Nodes: Decodable { let nodes: [Issue] }
        }
        return try decoder.decode(Response.self, from: data).data.viewer.assignedIssues.nodes
    }

    static func parseTeamsResponse(_ data: Data) throws -> [TeamWithCount] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let dataObj = json?["data"] as? [String: Any],
              let teams = dataObj["teams"] as? [String: Any],
              let nodes = teams["nodes"] as? [[String: Any]]
        else { throw LinearError.invalidResponse }
        return nodes.compactMap { node in
            guard let id = node["id"] as? String,
                  let key = node["key"] as? String,
                  let name = node["name"] as? String,
                  let color = node["color"] as? String
            else { return nil }
            let issues = (node["issues"] as? [String: Any])?["nodes"] as? [[String: Any]]
            let count = issues?.count ?? 0
            return TeamWithCount(team: Team(id: id, key: key, name: name, color: color), issueCount: count)
        }
    }

    static func parseWorkflowStatesResponse(_ data: Data) throws -> [WorkflowState] {
        struct Response: Decodable {
            let data: DataWrapper
            struct DataWrapper: Decodable { let team: TeamWrapper }
            struct TeamWrapper: Decodable { let states: Nodes }
            struct Nodes: Decodable { let nodes: [WorkflowState] }
        }
        return try decoder.decode(Response.self, from: data).data.team.states.nodes
    }

    static func parseMutationResponse(_ data: Data) throws -> Bool {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let dataObj = json?["data"] as? [String: Any] else {
            throw LinearError.invalidResponse
        }
        for (_, value) in dataObj {
            if let result = value as? [String: Any], let success = result["success"] as? Bool {
                return success
            }
        }
        throw LinearError.invalidResponse
    }

    // MARK: - Queries

    private static let viewerQuery = """
    { viewer { id name organization { name } } }
    """

    private static let issuesQuery = """
    { viewer { assignedIssues(filter: { snoozedBy: { null: true } }) { nodes { id identifier title description priority state { id name type color position } team { id key name color } url updatedAt createdAt } } } }
    """

    private static let teamsQuery = """
    { teams { nodes { id key name color issues(filter: { assignee: { isMe: { eq: true } } }) { nodes { id } } } } }
    """

    private static func workflowStatesQuery(teamId: String) -> String {
        """
        query { team(id: "\(teamId)") { states { nodes { id name type color position } } } }
        """
    }

    // MARK: - API Calls

    func validateAPIKey(_ key: String) async throws -> ViewerInfo {
        let request = try Self.buildRequest(query: Self.viewerQuery, apiKey: key)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.parseViewerResponse(data)
    }

    func fetchIssues() async throws -> [Issue] {
        guard let key = try keychainService.load() else { throw LinearError.noAPIKey }
        let request = try Self.buildRequest(query: Self.issuesQuery, apiKey: key)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.parseIssuesResponse(data)
    }

    func fetchTeams() async throws -> [TeamWithCount] {
        guard let key = try keychainService.load() else { throw LinearError.noAPIKey }
        let request = try Self.buildRequest(query: Self.teamsQuery, apiKey: key)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.parseTeamsResponse(data)
    }

    func fetchWorkflowStates(teamId: String) async throws -> [WorkflowState] {
        guard let key = try keychainService.load() else { throw LinearError.noAPIKey }
        let request = try Self.buildRequest(query: Self.workflowStatesQuery(teamId: teamId), apiKey: key)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.parseWorkflowStatesResponse(data)
    }

    func updateIssueStatus(issueId: String, stateId: String) async throws -> Bool {
        guard let key = try keychainService.load() else { throw LinearError.noAPIKey }
        let query = """
        mutation($id: String!, $stateId: String!) { issueUpdate(id: $id, input: { stateId: $stateId }) { success } }
        """
        let request = try Self.buildRequest(query: query, variables: ["id": issueId, "stateId": stateId], apiKey: key)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.parseMutationResponse(data)
    }

    func updateIssuePriority(issueId: String, priority: Int) async throws -> Bool {
        guard let key = try keychainService.load() else { throw LinearError.noAPIKey }
        let query = """
        mutation($id: String!, $priority: Int!) { issueUpdate(id: $id, input: { priority: $priority }) { success } }
        """
        let request = try Self.buildRequest(query: query, variables: ["id": issueId, "priority": priority], apiKey: key)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.parseMutationResponse(data)
    }

    func snoozeIssue(issueId: String, until: Date) async throws -> Bool {
        guard let key = try keychainService.load() else { throw LinearError.noAPIKey }
        let formatter = ISO8601DateFormatter()
        let query = """
        mutation($id: String!, $date: DateTime!) { issueUpdate(id: $id, input: { snoozedUntilAt: $date }) { success } }
        """
        let request = try Self.buildRequest(query: query, variables: ["id": issueId, "date": formatter.string(from: until)], apiKey: key)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.parseMutationResponse(data)
    }

    func deleteIssue(issueId: String) async throws -> Bool {
        guard let key = try keychainService.load() else { throw LinearError.noAPIKey }
        let query = """
        mutation($id: String!) { issueDelete(id: $id) { success } }
        """
        let request = try Self.buildRequest(query: query, variables: ["id": issueId], apiKey: key)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.parseMutationResponse(data)
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollingTask = Task { [weak appState] in
            guard let appState else { return }
            while !Task.isCancelled {
                await MainActor.run { appState.syncStatus = .syncing }
                do {
                    let issues = try await fetchIssues()
                    await MainActor.run {
                        appState.issues = issues
                        appState.syncStatus = .idle
                        appState.lastSyncDate = .now
                    }
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run { appState.syncStatus = .failed(lastAttempt: .now) }
                    }
                }
                let interval = await appState.pollingInterval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refreshNow() async {
        await MainActor.run { appState.syncStatus = .syncing }
        do {
            let issues = try await fetchIssues()
            await MainActor.run {
                appState.issues = issues
                appState.syncStatus = .idle
                appState.lastSyncDate = .now
            }
        } catch {
            await MainActor.run { appState.syncStatus = .failed(lastAttempt: .now) }
        }
    }
}

enum LinearError: Error {
    case noAPIKey
    case invalidResponse
    case mutationFailed
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
xcodebuild test -scheme lnr -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: all 5 parsing/request tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lnr/Services/LinearService.swift lnrTests/LinearServiceTests.swift
git commit -m "feat: add LinearService with GraphQL client, parsing, polling, and mutations"
```

---

## Task 6: AppDelegate — Menubar Icon & Popover Shell

**Files:**
- Create: `lnr/AppDelegate.swift`

- [ ] **Step 1: Implement AppDelegate**

```swift
// lnr/AppDelegate.swift
import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var appState: AppState!
    private var linearService: LinearService!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()
        linearService = LinearService(appState: appState)

        applyAppearance()
        setupStatusItem()
        setupPopover()
        observeState()
        checkInitialState()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.action = #selector(togglePopover)
        button.target = self
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        let symbolName: String
        let badgeText: String?
        let toolTip: String

        switch appState.connectionStatus {
        case .notConfigured:
            symbolName = "circle.circle"
            badgeText = nil
            toolTip = "lnr — Not configured"
        case .connecting:
            symbolName = "arrow.triangle.2.circlepath"
            badgeText = nil
            toolTip = "lnr — Connecting..."
        case .connected:
            switch appState.syncStatus {
            case .syncing:
                symbolName = "arrow.triangle.2.circlepath"
                badgeText = button.title.isEmpty ? nil : button.title
                toolTip = "lnr — Syncing..."
            case .failed:
                symbolName = "circle.circle"
                badgeText = button.title.isEmpty ? nil : button.title
                toolTip = "lnr — Last sync failed"
            case .idle:
                symbolName = "circle.circle"
                let count = appState.filteredIssues.count
                badgeText = (count > 0 && appState.showBadgeCount) ? "\(count)" : nil
                toolTip = count > 0 ? "lnr — \(count) issues" : "lnr — Connected"
            }
        case .error:
            symbolName = "circle.circle"
            badgeText = nil
            toolTip = "lnr — Last sync failed"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "lnr") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
        }
        button.title = badgeText ?? ""
        button.toolTip = toolTip

        if case .failed = appState.syncStatus, case .connected = appState.connectionStatus {
            addErrorBadge(to: button)
        } else if case .error = appState.connectionStatus {
            addErrorBadge(to: button)
        }
    }

    private func addErrorBadge(to button: NSStatusBarButton) {
        button.subviews.filter { $0.tag == 999 }.forEach { $0.removeFromSuperview() }
        let badge = NSImageView()
        badge.tag = 999
        badge.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "error")
        badge.contentTintColor = .systemRed
        badge.frame = NSRect(x: button.bounds.width - 10, y: 0, width: 8, height: 8)
        button.addSubview(badge)
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: Constants.popoverWidth, height: Constants.popoverMaxHeight)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView()
                .environmentObject(appState)
                .environment(\.linearService, linearService)
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - State Observation

    private func observeState() {
        appState.$issues
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        appState.$connectionStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        appState.$syncStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        appState.$showBadgeCount
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    // MARK: - Appearance

    private func applyAppearance() {
        switch UserDefaults.standard.string(forKey: Constants.Defaults.appearanceMode) {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    // MARK: - Initial State

    private func checkInitialState() {
        let keychain = KeychainService()
        guard let apiKey = try? keychain.load() else {
            appState.connectionStatus = .notConfigured
            return
        }
        appState.connectionStatus = .connecting
        Task {
            do {
                let viewer = try await linearService.validateAPIKey(apiKey)
                appState.connectionStatus = .connected(userName: viewer.name, orgName: viewer.orgName)
                let teamsWithCounts = try await linearService.fetchTeams()
                appState.teams = teamsWithCounts.map(\.team)
                if appState.selectedTeamIDs.isEmpty {
                    appState.selectedTeamIDs = Set(teamsWithCounts.filter { $0.issueCount > 0 }.map(\.team.id))
                }
                for team in appState.teams {
                    let states = try await linearService.fetchWorkflowStates(teamId: team.id)
                    appState.workflowStates[team.id] = states.sorted { $0.position < $1.position }
                }
                await linearService.startPolling()
            } catch {
                appState.connectionStatus = .error(message: error.localizedDescription)
            }
        }
    }
}
```

- [ ] **Step 2: Create LinearService environment key**

Add to `lnr/Services/LinearService.swift` at the bottom:

```swift
// MARK: - SwiftUI Environment

private struct LinearServiceKey: EnvironmentKey {
    static let defaultValue: LinearService? = nil
}

extension EnvironmentValues {
    var linearService: LinearService? {
        get { self[LinearServiceKey.self] }
        set { self[LinearServiceKey.self] = newValue }
    }
}
```

- [ ] **Step 3: Build — expect success**

```bash
xcodebuild build -scheme lnr -destination 'platform=macOS' 2>&1 | tail -10
```

Note: `PopoverContentView` doesn't exist yet — create a minimal stub for now.

- [ ] **Step 4: Commit**

```bash
git add lnr/AppDelegate.swift lnr/Services/LinearService.swift
git commit -m "feat: add AppDelegate with menubar icon states, popover, and Combine observation"
```

---

## Task 7: PopoverContentView — Root View Routing

**Files:**
- Create: `lnr/Views/PopoverContentView.swift`

- [ ] **Step 1: Implement PopoverContentView**

```swift
// lnr/Views/PopoverContentView.swift
import SwiftUI

struct PopoverContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.connectionStatus {
            case .notConfigured:
                if appState.onboardingComplete {
                    NotConfiguredView()
                } else {
                    OnboardingContainerView()
                }
            case .connecting:
                LoadingView(message: "Connecting...")
            case .connected:
                IssueListView()
            case .error(let message):
                if appState.issues.isEmpty {
                    ErrorView(message: message)
                } else {
                    IssueListView()
                }
            }
        }
        .frame(width: Constants.popoverWidth, height: Constants.popoverMaxHeight)
    }
}

struct NotConfiguredView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Connect to Linear")
                .font(.headline)
            Text("Add a Linear personal API key to start showing your assigned issues.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Open Settings...") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }
}

struct LoadingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct ErrorView: View {
    let message: String
    @Environment(\.linearService) var linearService

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Couldn't reach Linear")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Retry") {
                Task { await linearService?.refreshNow() }
            }
            Spacer()
        }
    }
}

struct OnboardingContainerView: View {
    @EnvironmentObject var appState: AppState
    @State private var step = 0

    var body: some View {
        VStack {
            switch step {
            case 0: WelcomeView(onContinue: { step = 1 })
            case 1: APIKeyView(onContinue: { step = 2 }, onSkip: { skipOnboarding() })
            case 2: TeamPickerView(onFinish: { finishOnboarding() }, onBack: { step = 1 })
            default: EmptyView()
            }

            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func skipOnboarding() {
        appState.onboardingComplete = true
        appState.savePreferences()
    }

    private func finishOnboarding() {
        appState.onboardingComplete = true
        appState.savePreferences()
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}
```

- [ ] **Step 2: Build — expect compilation errors for missing views**

The missing views (WelcomeView, APIKeyView, TeamPickerView, IssueListView) will be created in subsequent tasks. Create stubs:

```swift
// Temporary stubs — delete as real implementations are added
struct WelcomeView: View {
    let onContinue: () -> Void
    var body: some View { Button("Continue", action: onContinue) }
}

struct APIKeyView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void
    var body: some View { Button("Continue", action: onContinue) }
}

struct TeamPickerView: View {
    let onFinish: () -> Void
    let onBack: () -> Void
    var body: some View { Button("Finish", action: onFinish) }
}

struct IssueListView: View {
    var body: some View { Text("Issues") }
}
```

Put these stubs at the bottom of `PopoverContentView.swift`. They'll be replaced by real files.

- [ ] **Step 3: Build — expect success**

```bash
xcodebuild build -scheme lnr -destination 'platform=macOS' 2>&1 | tail -10
```

- [ ] **Step 4: Run the app to verify menubar icon appears**

```bash
xcodebuild build -scheme lnr -destination 'platform=macOS' && open lnr/build/Build/Products/Debug/lnr.app
```

Verify: ring+dot icon appears in menubar. Click it — popover shows the onboarding welcome stub.

- [ ] **Step 5: Commit**

```bash
git add lnr/Views/PopoverContentView.swift
git commit -m "feat: add PopoverContentView with routing for onboarding, issues, error, and loading"
```

---

## Task 8: Onboarding — WelcomeView

**Files:**
- Create: `lnr/Views/Onboarding/WelcomeView.swift`
- Modify: `lnr/Views/PopoverContentView.swift` (remove WelcomeView stub)

- [ ] **Step 1: Create WelcomeView**

```swift
// lnr/Views/Onboarding/WelcomeView.swift
import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "circle.circle")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.quaternary)
                )

            Text("Welcome to lnr")
                .font(.title2.bold())

            Text("Your Linear issues in the menubar.\nLightweight, native, and stays out of your way.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Get Started") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Takes about a minute")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
    }
}
```

- [ ] **Step 2: Remove stub from PopoverContentView.swift**

Delete the `WelcomeView` stub struct from PopoverContentView.swift.

- [ ] **Step 3: Build — expect success**

- [ ] **Step 4: Commit**

```bash
git add lnr/Views/Onboarding/WelcomeView.swift lnr/Views/PopoverContentView.swift
git commit -m "feat: add WelcomeView for onboarding step 1"
```

---

## Task 9: Onboarding — APIKeyView

**Files:**
- Create: `lnr/Views/Onboarding/APIKeyView.swift`
- Modify: `lnr/Views/PopoverContentView.swift` (remove APIKeyView stub)

- [ ] **Step 1: Create APIKeyView**

```swift
// lnr/Views/Onboarding/APIKeyView.swift
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
```

- [ ] **Step 2: Remove stub from PopoverContentView.swift**

- [ ] **Step 3: Build — expect success**

- [ ] **Step 4: Commit**

```bash
git add lnr/Views/Onboarding/APIKeyView.swift lnr/Views/PopoverContentView.swift
git commit -m "feat: add APIKeyView for onboarding step 2 with validation"
```

---

## Task 10: Onboarding — TeamPickerView

**Files:**
- Create: `lnr/Views/Onboarding/TeamPickerView.swift`
- Modify: `lnr/Views/PopoverContentView.swift` (remove TeamPickerView stub)

- [ ] **Step 1: Create TeamPickerView**

```swift
// lnr/Views/Onboarding/TeamPickerView.swift
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
                        issueCount: issueCount(for: team),
                        isSelected: appState.selectedTeamIDs.contains(team.id),
                        onToggle: { toggleTeam(team) }
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

    private func issueCount(for team: Team) -> Int {
        appState.issues.filter { $0.team.id == team.id }.count
    }

    private func toggleTeam(_ team: Team) {
        if appState.selectedTeamIDs.contains(team.id) {
            appState.selectedTeamIDs.remove(team.id)
        } else {
            appState.selectedTeamIDs.insert(team.id)
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
```

- [ ] **Step 2: Remove stub from PopoverContentView.swift**

- [ ] **Step 3: Build and test onboarding flow manually**

Run the app. Click menubar icon. Verify:
1. Welcome screen with "Get Started"
2. API key screen with SecureField, validation
3. Team picker with checkboxes
4. Finishing returns to main view

- [ ] **Step 4: Commit**

```bash
git add lnr/Views/Onboarding/TeamPickerView.swift lnr/Views/PopoverContentView.swift
git commit -m "feat: add TeamPickerView for onboarding step 3"
```

---

## Task 11: IssueRowView — Compact & Expanded

**Files:**
- Create: `lnr/Views/IssueList/IssueRowView.swift`

- [ ] **Step 1: Create IssueRowView**

```swift
// lnr/Views/IssueList/IssueRowView.swift
import SwiftUI

struct IssueRowView: View {
    let issue: Issue
    let isExpanded: Bool
    let isSelected: Bool
    let onToggleExpand: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            compactRow
            if isExpanded {
                expandedContent
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    // MARK: - Compact Row

    private var compactRow: some View {
        HStack(spacing: 6) {
            priorityIcon
                .frame(width: 16, height: 16)

            Circle()
                .fill(Color(hex: issue.state.color))
                .frame(width: 8, height: 8)

            Text(issue.identifier)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            Text(issue.title)
                .font(.body)
                .lineLimit(1)

            Spacer()

            Text(issue.relativeTimestamp)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var priorityIcon: some View {
        switch issue.priority {
        case 1:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        case 2:
            PriorityBars(level: 3)
        case 3:
            PriorityBars(level: 2)
        case 4:
            PriorityBars(level: 1)
        default:
            Image(systemName: "circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(issue.identifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                StatusPill(state: issue.state)

                Spacer()
            }
            .padding(.top, 8)

            Text(issue.title)
                .font(.body.bold())
                .lineLimit(2)

            if let desc = issue.strippedDescription, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: issue.team.color))
                        .frame(width: 6, height: 6)
                    Text(issue.team.key)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("·")
                    .foregroundStyle(.tertiary)

                Text(issue.relativeTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button { onOpen() } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Open in Linear") { onOpen() }
                    Button("Copy link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(issue.url, forType: .string)
                    }
                    Button("Copy identifier") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(issue.identifier, forType: .string)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button("Open in Linear") { onOpen() }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding(.leading, 30)
    }
}

// MARK: - Supporting Views

struct PriorityBars: View {
    let level: Int

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(i < level ? Color.orange : Color.secondary.opacity(0.2))
                    .frame(width: 3, height: CGFloat(4 + i * 2))
            }
        }
        .frame(width: 16, height: 16, alignment: .bottom)
    }
}

struct StatusPill: View {
    let state: WorkflowState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: state.color))
                .frame(width: 6, height: 6)
            Text(state.name)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color(hex: state.color).opacity(0.15)))
    }
}
```

- [ ] **Step 2: Build — expect success**

- [ ] **Step 3: Commit**

```bash
git add lnr/Views/IssueList/IssueRowView.swift
git commit -m "feat: add IssueRowView with compact and expanded states"
```

---

## Task 12: EmptyStateView

**Files:**
- Create: `lnr/Views/IssueList/EmptyStateView.swift`

- [ ] **Step 1: Create EmptyStateView**

```swift
// lnr/Views/IssueList/EmptyStateView.swift
import SwiftUI

struct EmptyStateView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("Inbox zero.")
                .font(.headline)

            Text("No issues assigned to you. lnr will check again in \(intervalLabel).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var intervalLabel: String {
        let interval = Int(appState.pollingInterval)
        if interval < 60 { return "\(interval)s" }
        let minutes = interval / 60
        return "\(minutes)m"
    }
}
```

- [ ] **Step 2: Build — expect success**

- [ ] **Step 3: Commit**

```bash
git add lnr/Views/IssueList/EmptyStateView.swift
git commit -m "feat: add EmptyStateView for inbox zero"
```

---

## Task 13: IssueListView — Header, Search, Flat & Grouped

**Files:**
- Create: `lnr/Views/IssueList/IssueListView.swift` (real implementation, replacing stub)
- Create: `lnr/Views/IssueList/FlatListView.swift`
- Create: `lnr/Views/IssueList/GroupedListView.swift`
- Modify: `lnr/Views/PopoverContentView.swift` (remove IssueListView stub)

- [ ] **Step 1: Create FlatListView**

```swift
// lnr/Views/IssueList/FlatListView.swift
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
        if let url = URL(string: issue.url) {
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [ ] **Step 2: Create GroupedListView**

```swift
// lnr/Views/IssueList/GroupedListView.swift
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
}
```

- [ ] **Step 3: Create full IssueListView**

```swift
// lnr/Views/IssueList/IssueListView.swift
import SwiftUI

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
    }

    // MARK: - Header

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
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
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
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.caption)
                }

                Button {
                    appState.viewMode = appState.viewMode == .flat ? .groupedByState : .flat
                    appState.savePreferences()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.caption)
                        .symbolVariant(appState.viewMode == .groupedByState ? .fill : .none)
                }
                .buttonStyle(.plain)

                Button {
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField("Search \(appState.filteredIssues.count) issues...", text: $appState.searchText)
                .textFieldStyle(.plain)
                .font(.body)
            if !appState.searchText.isEmpty {
                Button { appState.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
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

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if case .syncing = appState.syncStatus, appState.issues.isEmpty {
            LoadingView(message: "Loading issues...")
        } else if appState.filteredIssues.isEmpty {
            EmptyStateView()
        } else {
            switch appState.viewMode {
            case .flat:
                FlatListView()
            case .groupedByState:
                GroupedListView()
            }
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            HStack(spacing: 12) {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                    Image(systemName: "arrow.down")
                }
                .font(.caption2)
                .foregroundStyle(.quaternary)

                Text("navigate")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)

                HStack(spacing: 2) {
                    Image(systemName: "return")
                }
                .font(.caption2)
                .foregroundStyle(.quaternary)

                Text("open")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }

            Spacer()

            Text(syncStatusLabel)
                .font(.caption2)
                .foregroundStyle(.quaternary)
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
        case .syncing:
            return "Syncing..."
        case .failed:
            return "Sync failed"
        }
    }
}
```

- [ ] **Step 4: Remove IssueListView stub from PopoverContentView.swift**

`IssueContextMenu` doesn't exist yet — create a minimal stub at the bottom of `IssueListView.swift`:

```swift
struct IssueContextMenu: View {
    let issue: Issue
    var body: some View {
        Button("Open in Linear") {
            if let url = URL(string: issue.url) { NSWorkspace.shared.open(url) }
        }
    }
}
```

This stub will be replaced in Task 14.

- [ ] **Step 5: Build and run**

Verify: popover shows header with Inbox label, search bar, footer with sync status. If connected with issues, the flat list renders rows. Toggle to grouped view works.

- [ ] **Step 6: Commit**

```bash
git add lnr/Views/IssueList/ lnr/Views/PopoverContentView.swift
git commit -m "feat: add IssueListView with header, search, flat and grouped views"
```

---

## Task 14: Context Menu — Full Actions

**Files:**
- Create: `lnr/Views/IssueList/IssueContextMenu.swift` (replaces stub)
- Modify: `lnr/Views/IssueList/IssueListView.swift` (remove IssueContextMenu stub)

- [ ] **Step 1: Create IssueContextMenu**

```swift
// lnr/Views/IssueList/IssueContextMenu.swift
import SwiftUI

struct IssueContextMenu: View {
    let issue: Issue
    @EnvironmentObject var appState: AppState
    @Environment(\.linearService) var linearService

    var body: some View {
        Button("Open in Linear") { openInLinear() }
            .keyboardShortcut("o", modifiers: .command)

        Button("Copy link") { copyToClipboard(issue.url) }
            .keyboardShortcut("l", modifiers: .command)

        Button("Copy identifier") { copyToClipboard(issue.identifier) }
            .keyboardShortcut(".", modifiers: .command)

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
                        Circle()
                            .fill(Color(hex: state.color))
                            .frame(width: 8, height: 8)
                        Text(state.name)
                    }
                }
            }
        }

        Menu("Set priority...") {
            ForEach([(1, "Urgent"), (2, "High"), (3, "Medium"), (4, "Low"), (0, "None")], id: \.0) { value, label in
                Button {
                    changePriority(to: value)
                } label: {
                    HStack {
                        if issue.priority == value {
                            Image(systemName: "checkmark")
                        }
                        Text(label)
                    }
                }
            }
        }

        Menu("Snooze...") {
            Button("1 hour") { snooze(hours: 1) }
            Button("4 hours") { snooze(hours: 4) }
            Button("Tomorrow") { snoozeTomorrow() }
            Button("Next week") { snoozeNextWeek() }
        }

        Divider()

        Button(role: .destructive) { deleteIssue() } label: {
            Text("Delete")
        }
    }

    // MARK: - Actions

    private func openInLinear() {
        let openIn = UserDefaults.standard.string(forKey: Constants.Defaults.openIssuesIn) ?? "browser"
        if openIn == "linear", let linearURL = URL(string: issue.url.replacingOccurrences(of: "https://linear.app", with: "linear://")) {
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
            } catch {
                revert { $0.state = oldState }
            }
        }
    }

    private func changePriority(to priority: Int) {
        let oldPriority = issue.priority
        optimisticUpdate { $0.priority = priority }
        Task {
            do {
                let success = try await linearService?.updateIssuePriority(issueId: issue.id, priority: priority) ?? false
                if !success { revert { $0.priority = oldPriority } }
            } catch {
                revert { $0.priority = oldPriority }
            }
        }
    }

    private func snooze(hours: Int) {
        let until = Calendar.current.date(byAdding: .hour, value: hours, to: .now) ?? .now
        removeFromList()
        Task {
            _ = try? await linearService?.snoozeIssue(issueId: issue.id, until: until)
        }
    }

    private func snoozeTomorrow() {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        comps.day! += 1
        comps.hour = 9
        let until = Calendar.current.date(from: comps) ?? .now
        removeFromList()
        Task {
            _ = try? await linearService?.snoozeIssue(issueId: issue.id, until: until)
        }
    }

    private func snoozeNextWeek() {
        let until = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 9, weekday: 2), matchingPolicy: .nextTime) ?? .now
        removeFromList()
        Task {
            _ = try? await linearService?.snoozeIssue(issueId: issue.id, until: until)
        }
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
            Task {
                _ = try? await linearService?.deleteIssue(issueId: issue.id)
            }
        }
    }

    // MARK: - Helpers

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
```

- [ ] **Step 2: Remove IssueContextMenu stub from IssueListView.swift**

- [ ] **Step 4: Build — expect success**

- [ ] **Step 5: Run and test context menu**

Right-click an issue row. Verify: all menu items appear. Test "Copy identifier" — should copy to clipboard.

- [ ] **Step 6: Commit**

```bash
git add lnr/Views/IssueList/IssueContextMenu.swift lnr/Views/IssueList/IssueListView.swift lnr/Models/Issue.swift
git commit -m "feat: add full context menu with status, priority, snooze, delete actions"
```

---

## Task 15: Settings Window

**Files:**
- Create: `lnr/Views/Settings/SettingsWindowController.swift`
- Create: `lnr/Views/Settings/GeneralSettingsView.swift`
- Create: `lnr/Views/Settings/AccountSettingsView.swift`
- Create: `lnr/Views/Settings/ShortcutsSettingsView.swift`
- Create: `lnr/Views/Settings/AdvancedSettingsView.swift`
- Modify: `lnr/AppDelegate.swift` (observe .openSettings notification)

- [ ] **Step 1: Create SettingsWindowController**

```swift
// lnr/Views/Settings/SettingsWindowController.swift
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let appState: AppState
    private let linearService: LinearService

    init(appState: AppState, linearService: LinearService) {
        self.appState = appState
        self.linearService = linearService
    }

    func showWindow() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsTabView()
            .environmentObject(appState)
            .environment(\.linearService, linearService)

        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "lnr Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: Constants.settingsWidth, height: Constants.settingsHeight))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

struct SettingsTabView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AccountSettingsView()
                .tabItem { Label("Account", systemImage: "person") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "square.grid.2x2") }
        }
        .frame(width: Constants.settingsWidth, height: Constants.settingsHeight)
    }
}
```

- [ ] **Step 2: Create GeneralSettingsView**

```swift
// lnr/Views/Settings/GeneralSettingsView.swift
import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Picker("Refresh interval", selection: $appState.pollingInterval) {
                Text("30s").tag(TimeInterval(30))
                Text("60s").tag(TimeInterval(60))
                Text("2m").tag(TimeInterval(120))
                Text("5m").tag(TimeInterval(300))
                Text("10m").tag(TimeInterval(600))
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = !newValue
                    }
                }

            Toggle("Show badge count on icon", isOn: $appState.showBadgeCount)

            Picker("Appearance", selection: Binding(
                get: { UserDefaults.standard.string(forKey: Constants.Defaults.appearanceMode) ?? "system" },
                set: { newValue in
                    UserDefaults.standard.set(newValue, forKey: Constants.Defaults.appearanceMode)
                    switch newValue {
                    case "light": NSApp.appearance = NSAppearance(named: .aqua)
                    case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
                    default: NSApp.appearance = nil
                    }
                }
            )) {
                Text("Light").tag("light")
                Text("Dark").tag("dark")
                Text("System").tag("system")
            }
            .pickerStyle(.segmented)

            Picker("Open issues in", selection: Binding(
                get: { UserDefaults.standard.string(forKey: Constants.Defaults.openIssuesIn) ?? "browser" },
                set: { UserDefaults.standard.set($0, forKey: Constants.Defaults.openIssuesIn) }
            )) {
                Text("Default browser").tag("browser")
                Text("Linear desktop app").tag("linear")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

- [ ] **Step 3: Create AccountSettingsView**

```swift
// lnr/Views/Settings/AccountSettingsView.swift
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
                        SecureField("lin_api_...", text: $newKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") { replaceKey() }
                            .disabled(newKey.count < 10 || isValidating)
                        Button("Cancel") { isReplacing = false; newKey = "" }
                    }
                } else {
                    HStack {
                        Text(maskedKey)
                            .font(.body.monospaced())
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
                    HStack {
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
        let prefix = String(key.prefix(8))
        return prefix + String(repeating: "•", count: 20)
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
```

- [ ] **Step 4: Create ShortcutsSettingsView**

```swift
// lnr/Views/Settings/ShortcutsSettingsView.swift
import SwiftUI

struct ShortcutsSettingsView: View {
    private let shortcuts: [(String, String)] = [
        ("⌘O", "Open in Linear"),
        ("⌘L", "Copy link"),
        ("⌘.", "Copy identifier"),
        ("⌘⌫", "Delete issue"),
        ("⌘K", "Focus search"),
        ("↑↓", "Navigate issues"),
        ("↩", "Open selected issue"),
        ("Space", "Expand / collapse"),
    ]

    var body: some View {
        Form {
            Section("Keyboard Shortcuts") {
                ForEach(shortcuts, id: \.0) { shortcut, action in
                    HStack {
                        Text(shortcut)
                            .font(.body.monospaced())
                            .frame(width: 60, alignment: .trailing)
                        Text(action)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

- [ ] **Step 5: Create AdvancedSettingsView**

```swift
// lnr/Views/Settings/AdvancedSettingsView.swift
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
```

- [ ] **Step 6: Wire settings notification in AppDelegate**

Add to `AppDelegate.applicationDidFinishLaunching`, after `checkInitialState()`:

```swift
NotificationCenter.default.addObserver(forName: .openSettings, object: nil, queue: .main) { [weak self] _ in
    self?.settingsController?.showWindow()
}
```

Add property to AppDelegate:

```swift
private var settingsController: SettingsWindowController?
```

Initialize it in `applicationDidFinishLaunching` after creating `linearService`:

```swift
settingsController = SettingsWindowController(appState: appState, linearService: linearService)
```

- [ ] **Step 7: Build and run**

Click gear in popover header → Settings window opens. Verify all four tabs render.

- [ ] **Step 8: Commit**

```bash
git add lnr/Views/Settings/ lnr/AppDelegate.swift
git commit -m "feat: add Settings window with General, Account, Shortcuts, and Advanced tabs"
```

---

## Task 16: Keyboard Navigation

**Files:**
- Modify: `lnr/Views/IssueList/IssueListView.swift`

- [ ] **Step 1: Add keyboard event handling**

Add `.onKeyPress` modifiers to the `IssueListView` body (macOS 14+):

In `IssueListView`, wrap the main `VStack` content area with keyboard handlers. Add this modifier to the outermost `VStack` in `IssueListView.body`:

```swift
.onKeyPress(.upArrow) { navigateIssues(direction: -1); return .handled }
.onKeyPress(.downArrow) { navigateIssues(direction: 1); return .handled }
.onKeyPress(.return) { openSelectedIssue(); return .handled }
.onKeyPress(.space) { toggleSelectedExpansion(); return .handled }
.onKeyPress(characters: "k", modifiers: .command) { isSearchFocused = true; return .handled }
```

Add these methods to `IssueListView`:

```swift
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
```

- [ ] **Step 2: Build and test**

Run app. Use arrow keys to navigate, Space to expand, Return to open.

- [ ] **Step 3: Commit**

```bash
git add lnr/Views/IssueList/IssueListView.swift
git commit -m "feat: add keyboard navigation for issue list"
```

---

## Task 17: Polish & Info.plist

**Files:**
- Modify: `lnr/Info.plist` or Xcode target settings
- Modify: `lnr/lnrApp.swift`

- [ ] **Step 1: Configure as agent app (no dock icon)**

Add to Info.plist (or via Xcode target → Info):

```xml
<key>LSUIElement</key>
<true/>
```

This makes the app a menubar-only agent — no Dock icon, no main window.

- [ ] **Step 2: Set app metadata**

In Xcode target settings:
- Bundle Identifier: `com.lnr.app`
- Version: `1.0.0`
- Build: `1`
- Deployment Target: macOS 14.0
- App Category: Productivity

- [ ] **Step 3: Build and run full flow**

Test the complete flow:
1. App launches — ring+dot icon in menubar, no dock icon
2. Click icon — onboarding welcome appears
3. Enter API key — validates, shows green confirmation
4. Pick teams — select teams, finish
5. Issue list loads — flat view with issues
6. Toggle grouped view — tabs and sections appear
7. Search — filters issues
8. Right-click — full context menu
9. Keyboard nav — arrows, space, return all work
10. Settings — gear opens settings window, all tabs work
11. Sign out — returns to not-configured state

- [ ] **Step 4: Commit**

```bash
git add .
git commit -m "feat: configure as agent app, set bundle metadata"
```
