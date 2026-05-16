import Foundation

enum StateType: String, Codable, CaseIterable {
    case triage
    case backlog
    case unstarted
    case started
    case completed
    case cancelled

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = StateType(rawValue: raw) ?? .backlog
    }
}

struct WorkflowState: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: StateType
    let color: String
    let position: Double
}
