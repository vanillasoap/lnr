import Foundation

enum Formatters {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

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
        Formatters.relative.localizedString(for: updatedAt, relativeTo: .now)
    }

    var strippedDescription: String? {
        guard let description else { return nil }
        return description
            .replacingOccurrences(of: #"[#*_~`>\[\]()!]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
