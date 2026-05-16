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
                if appState.onboardingComplete {
                    IssueListView()
                } else {
                    OnboardingContainerView()
                }
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
                ForEach(0..<3, id: \.self) { i in
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

