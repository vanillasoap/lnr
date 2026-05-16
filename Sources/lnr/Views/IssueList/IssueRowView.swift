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
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }

    private var compactRow: some View {
        HStack(spacing: 8) {
            priorityIcon
                .frame(width: 18, height: 18)
            StateIcon(state: issue.state, size: 10)
            Text(issue.identifier)
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
            Text(issue.title)
                .font(.body)
                .lineLimit(1)
            Spacer()
            Text(issue.relativeTimestamp)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var priorityIcon: some View {
        switch issue.priority {
        case 1: UrgentBadge()
        case 2: PriorityBars(level: 3, color: .secondary)
        case 3: PriorityBars(level: 2, color: .secondary)
        case 4: PriorityBars(level: 1, color: .secondary)
        default:
            PriorityBars(level: 0, color: .secondary)
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(issue.identifier)
                    .font(.subheadline.monospaced())
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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: issue.team.color))
                        .frame(width: 7, height: 7)
                    Text(issue.team.key)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("·").foregroundStyle(.tertiary)
                Text(issue.relativeTimestamp)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button { onOpen() } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.subheadline)
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
                        .font(.subheadline)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button("Open in Linear") { onOpen() }
                    .font(.subheadline)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding(.leading, 34)
    }
}

struct UrgentBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3.5)
                .fill(Color.orange)
            Text("!")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: 16, height: 16)
    }
}

struct PriorityBars: View {
    let level: Int
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(i < level ? color : Color.secondary.opacity(0.15))
                    .frame(width: 3, height: CGFloat(4 + i * 2))
            }
        }
        .frame(width: 16, height: 16, alignment: .bottom)
    }
}

struct StateIcon: View {
    let state: WorkflowState
    var size: CGFloat = 10

    var body: some View {
        Image(systemName: symbolName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(Color(hex: state.color))
    }

    private var symbolName: String {
        switch state.type {
        case .triage: "circle.dashed"
        case .backlog: "circle.dashed"
        case .unstarted: "circle"
        case .started: "circle.lefthalf.filled"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }
}

struct StatusPill: View {
    let state: WorkflowState
    var body: some View {
        HStack(spacing: 4) {
            StateIcon(state: state, size: 8)
            Text(state.name)
                .font(.caption)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color(hex: state.color).opacity(0.15)))
    }
}
