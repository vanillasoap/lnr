import Foundation
import SwiftUI

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
        let query = "mutation($id: String!, $stateId: String!) { issueUpdate(id: $id, input: { stateId: $stateId }) { success } }"
        let request = try Self.buildRequest(query: query, variables: ["id": issueId, "stateId": stateId], apiKey: key)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.parseMutationResponse(data)
    }

    func updateIssuePriority(issueId: String, priority: Int) async throws -> Bool {
        guard let key = try keychainService.load() else { throw LinearError.noAPIKey }
        let query = "mutation($id: String!, $priority: Int!) { issueUpdate(id: $id, input: { priority: $priority }) { success } }"
        let request = try Self.buildRequest(query: query, variables: ["id": issueId, "priority": priority], apiKey: key)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.parseMutationResponse(data)
    }

    func snoozeIssue(issueId: String, until: Date) async throws -> Bool {
        guard let key = try keychainService.load() else { throw LinearError.noAPIKey }
        let formatter = ISO8601DateFormatter()
        let query = "mutation($id: String!, $date: DateTime!) { issueUpdate(id: $id, input: { snoozedUntilAt: $date }) { success } }"
        let request = try Self.buildRequest(query: query, variables: ["id": issueId, "date": formatter.string(from: until)], apiKey: key)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try Self.parseMutationResponse(data)
    }

    func deleteIssue(issueId: String) async throws -> Bool {
        guard let key = try keychainService.load() else { throw LinearError.noAPIKey }
        let query = "mutation($id: String!) { issueDelete(id: $id) { success } }"
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
