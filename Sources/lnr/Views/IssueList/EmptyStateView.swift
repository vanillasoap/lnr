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
