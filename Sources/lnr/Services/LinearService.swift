import Foundation
import SwiftUI
import os.log

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

    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "network")

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = ["User-Agent": "lnr/1.0 (macOS)"]
        return URLSession(configuration: config)
    }()

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

    struct GraphQLError: Decodable { let message: String }
    struct GraphQLResponse<DataType: Decodable>: Decodable {
        let data: DataType?
        let errors: [GraphQLError]?
    }

    static func parseViewerResponse(_ data: Data) throws -> ViewerInfo {
        struct ViewerData: Decodable { let viewer: Viewer }
        struct Viewer: Decodable { let id: String; let name: String; let organization: Organization }
        struct Organization: Decodable { let name: String }
        let wrapper = try decoder.decode(GraphQLResponse<ViewerData>.self, from: data)
        if let errors = wrapper.errors, !errors.isEmpty { throw LinearError.invalidResponse }
        guard let v = wrapper.data?.viewer else { throw LinearError.invalidResponse }
        return ViewerInfo(id: v.id, name: v.name, orgName: v.organization.name)
    }

    static func parseIssuesResponse(_ data: Data) throws -> [Issue] {
        struct Response: Decodable {
            let viewer: Viewer
            struct Viewer: Decodable { let assignedIssues: Nodes }
            struct Nodes: Decodable { let nodes: [Issue] }
        }
        let wrapper = try decoder.decode(GraphQLResponse<Response>.self, from: data)
        if let errors = wrapper.errors, !errors.isEmpty { throw LinearError.invalidResponse }
        guard let payload = wrapper.data else { throw LinearError.invalidResponse }
        return payload.viewer.assignedIssues.nodes
    }

    static func parseTeamsResponse(_ data: Data) throws -> [TeamWithCount] {
        struct Response: Decodable {
            let teams: Teams
            struct Teams: Decodable { let nodes: [Node] }
            struct Node: Decodable {
                let id: String
                let key: String
                let name: String
                let color: String
                let issues: Issues
                struct Issues: Decodable { let nodes: [IssueRef] }
                struct IssueRef: Decodable { let id: String }
            }
        }
        let wrapper = try decoder.decode(GraphQLResponse<Response>.self, from: data)
        if let errors = wrapper.errors, !errors.isEmpty { throw LinearError.invalidResponse }
        guard let payload = wrapper.data else { throw LinearError.invalidResponse }
        return payload.teams.nodes.map { node in
            TeamWithCount(team: Team(id: node.id, key: node.key, name: node.name, color: node.color), issueCount: node.issues.nodes.count)
        }
    }

    static func parseWorkflowStatesResponse(_ data: Data) throws -> [WorkflowState] {
        struct Response: Decodable {
            let team: TeamWrapper
            struct TeamWrapper: Decodable { let states: Nodes }
            struct Nodes: Decodable { let nodes: [WorkflowState] }
        }
        let wrapper = try decoder.decode(GraphQLResponse<Response>.self, from: data)
        if let errors = wrapper.errors, !errors.isEmpty { throw LinearError.invalidResponse }
        guard let payload = wrapper.data else { throw LinearError.invalidResponse }
        return payload.team.states.nodes
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

    private static let viewerQuery = "{ viewer { id name organization { name } } }"

    private static let issuesQuery = """
    { viewer { assignedIssues(filter: { snoozedBy: { null: true } }) { nodes { id identifier title description priority state { id name type color position } team { id key name color } url updatedAt createdAt } } } }
    """

    private static let teamsQuery = """
    { teams { nodes { id key name color issues(filter: { assignee: { isMe: { eq: true } } }) { nodes { id } } } } }
    """

    private static func workflowStatesQuery(teamId: String) -> String {
        "query { team(id: \"\(teamId)\") { states { nodes { id name type color position } } } }"
    }

    // MARK: - API Calls

    func validateAPIKey(_ key: String) async throws -> ViewerInfo {
        let request = try Self.buildRequest(query: Self.viewerQuery, apiKey: key)
        let (data, _) = try await Self.session.data(for: request)
        return try Self.parseViewerResponse(data)
    }

    func fetchIssues() async throws -> [Issue] {
        guard let key = try keychainService.load() else { throw LinearError.noAPIKey }
        let request = try Self.buildRequest(query: Self.issuesQuery, apiKey: key)
        let (data, _) = try await Self.session.data(for: request)
        return try Self.parseIssuesResponse(data)
    }

    func fetchTeams() async throws -> [TeamWithCount] {
        guard let key = try keychainService.load() else { throw LinearError.noAPIKey }
        let request = try Self.buildRequest(query: Self.teamsQuery, apiKey: key)
        let (data, _) = try await Self.session.data(for: request)
        return try Self.parseTeamsResponse(data)
    }

    func fetchWorkflowStates(teamId: String) async throws -> [WorkflowState] {
        guard let key = try keychainService.load() else { throw LinearError.noAPIKey }
        let request = try Self.buildRequest(query: Self.workflowStatesQuery(teamId: teamId), apiKey: key)
        let (data, _) = try await Self.session.data(for: request)
        return try Self.parseWorkflowStatesResponse(data)
    }

    func updateIssueStatus(issueId: String, stateId: String) async throws -> Bool {
        guard let key = try keychainService.load() else { throw LinearError.noAPIKey }
        let query = "mutation($id: String!, $stateId: String!) { issueUpdate(id: $id, input: { stateId: $stateId }) { success } }"
        let request = try Self.buildRequest(query: query, variables: ["id": issueId, "stateId": stateId], apiKey: key)
        let (data, _) = try await Self.session.data(for: request)
        return try Self.parseMutationResponse(data)
    }

    func updateIssuePriority(issueId: String, priority: Int) async throws -> Bool {
        guard let key = try keychainService.load() else { throw LinearError.noAPIKey }
        let query = "mutation($id: String!, $priority: Int!) { issueUpdate(id: $id, input: { priority: $priority }) { success } }"
        let request = try Self.buildRequest(query: query, variables: ["id": issueId, "priority": priority], apiKey: key)
        let (data, _) = try await Self.session.data(for: request)
        return try Self.parseMutationResponse(data)
    }

    func snoozeIssue(issueId: String, until: Date) async throws -> Bool {
        guard let key = try keychainService.load() else { throw LinearError.noAPIKey }
        let formatter = ISO8601DateFormatter()
        let query = "mutation($id: String!, $date: DateTime!) { issueUpdate(id: $id, input: { snoozedUntilAt: $date }) { success } }"
        let request = try Self.buildRequest(query: query, variables: ["id": issueId, "date": formatter.string(from: until)], apiKey: key)
        let (data, _) = try await Self.session.data(for: request)
        return try Self.parseMutationResponse(data)
    }

    func deleteIssue(issueId: String) async throws -> Bool {
        guard let key = try keychainService.load() else { throw LinearError.noAPIKey }
        let query = "mutation($id: String!) { issueDelete(id: $id) { success } }"
        let request = try Self.buildRequest(query: query, variables: ["id": issueId], apiKey: key)
        let (data, _) = try await Self.session.data(for: request)
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
                    self.logger.error("[lnr] polling fetch failed: \(String(describing: error), privacy: .public)")
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

// MARK: - SwiftUI Environment Key

private struct LinearServiceKey: EnvironmentKey {
    static let defaultValue: LinearService? = nil
}

extension EnvironmentValues {
    var linearService: LinearService? {
        get { self[LinearServiceKey.self] }
        set { self[LinearServiceKey.self] = newValue }
    }
}
