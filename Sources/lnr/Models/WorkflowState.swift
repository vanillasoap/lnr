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
