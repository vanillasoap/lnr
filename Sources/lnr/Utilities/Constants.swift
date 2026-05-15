import Foundation

enum Constants {
    static let popoverWidth: CGFloat = 360
    static let popoverMaxHeight: CGFloat = 500
    static let settingsWidth: CGFloat = 480
    static let settingsHeight: CGFloat = 400
    static let linearAPIURL = URL(string: "https://api.linear.app/graphql")!
    static let defaultPollingInterval: TimeInterval = 60

    enum Defaults {
        static let pollingInterval = "pollingInterval"
        static let viewMode = "viewMode"
        static let sortOrder = "sortOrder"
        static let selectedTeamIDs = "selectedTeamIDs"
        static let showBadgeCount = "showBadgeCount"
        static let appearanceMode = "appearanceMode"
        static let openIssuesIn = "openIssuesIn"
        static let onboardingComplete = "onboardingComplete"
    }
}
