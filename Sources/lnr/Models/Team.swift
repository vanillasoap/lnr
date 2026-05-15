import Foundation

struct Team: Codable, Identifiable, Hashable {
    let id: String
    let key: String
    let name: String
    let color: String
}
