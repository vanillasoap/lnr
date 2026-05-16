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
        case 1: PriorityBars(level: 3, color: .orange)
        case 2: PriorityBars(level: 3, color: .orange)
        case 3: PriorityBars(level: 2, color: .yellow)
        case 4: PriorityBars(level: 1, color: .blue)
        default:
            PriorityBars(level: 0, color: .secondary.opacity(0.3))
        }
    }

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
                Text("·").foregroundStyle(.tertiary)
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

struct PriorityBars: View {
    let level: Int
    let color: Color

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(i < level ? color : Color.secondary.opacity(0.15))
                    .frame(width: 2.5, height: CGFloat(3 + i * 2))
            }
        }
        .frame(width: 14, height: 14, alignment: .bottom)
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
