import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var appState: AppState!
    private var linearService: LinearService!
    private var cancellables = Set<AnyCancellable>()
    private var settingsController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()
        linearService = LinearService(appState: appState)
        settingsController = SettingsWindowController(appState: appState, linearService: linearService)

        applyAppearance()
        setupStatusItem()
        setupPopover()
        observeState()
        checkInitialState()

        NotificationCenter.default.addObserver(forName: .openSettings, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.settingsController?.showWindow()
            }
        }
    }

    // MARK: - Appearance

    private func applyAppearance() {
        switch UserDefaults.standard.string(forKey: Constants.Defaults.appearanceMode) {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.action = #selector(togglePopover)
        button.target = self
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.subviews.filter { $0.tag == 999 }.forEach { $0.removeFromSuperview() }

        let symbolName: String
        let badgeText: String?
        let toolTip: String

        switch appState.connectionStatus {
        case .notConfigured:
            symbolName = "circle.circle"
            badgeText = nil
            toolTip = "lnr — Not configured"
        case .connecting:
            symbolName = "arrow.triangle.2.circlepath"
            badgeText = nil
            toolTip = "lnr — Connecting..."
        case .connected:
            switch appState.syncStatus {
            case .syncing:
                symbolName = "arrow.triangle.2.circlepath"
                badgeText = button.title.isEmpty ? nil : button.title
                toolTip = "lnr — Syncing..."
            case .failed:
                symbolName = "circle.circle"
                badgeText = button.title.isEmpty ? nil : button.title
                toolTip = "lnr — Last sync failed"
            case .idle:
                symbolName = "circle.circle"
                let count = appState.filteredIssues.count
                badgeText = (count > 0 && appState.showBadgeCount) ? "\(count)" : nil
                toolTip = count > 0 ? "lnr — \(count) issues" : "lnr — Connected"
            }
        case .error:
            symbolName = "circle.circle"
            badgeText = nil
            toolTip = "lnr — Last sync failed"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "lnr") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
        }
        button.title = badgeText ?? ""
        button.toolTip = toolTip

        if case .failed = appState.syncStatus, case .connected = appState.connectionStatus {
            addErrorBadge(to: button)
        } else if case .error = appState.connectionStatus {
            addErrorBadge(to: button)
        }
    }

    private func addErrorBadge(to button: NSStatusBarButton) {
        let badge = NSImageView()
        badge.tag = 999
        badge.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "error")
        badge.contentTintColor = .systemRed
        badge.frame = NSRect(x: button.bounds.width - 10, y: 0, width: 8, height: 8)
        button.addSubview(badge)
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: Constants.popoverWidth, height: Constants.popoverMaxHeight)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverContentView()
                .environmentObject(appState)
                .environment(\.linearService, linearService)
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - State Observation

    private func observeState() {
        appState.$issues
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        appState.$connectionStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        appState.$syncStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)

        appState.$showBadgeCount
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
    }

    // MARK: - Initial State

    private func checkInitialState() {
        let keychain = KeychainService()
        guard let apiKey = try? keychain.load() else {
            appState.connectionStatus = .notConfigured
            return
        }
        appState.connectionStatus = .connecting
        Task {
            do {
                let viewer = try await linearService.validateAPIKey(apiKey)
                appState.connectionStatus = .connected(userName: viewer.name, orgName: viewer.orgName)
                let teamsWithCounts = try await linearService.fetchTeams()
                appState.teams = teamsWithCounts.map(\.team)
                if appState.selectedTeamIDs.isEmpty {
                    appState.selectedTeamIDs = Set(teamsWithCounts.filter { $0.issueCount > 0 }.map(\.team.id))
                }
                for team in appState.teams {
                    let states = try await linearService.fetchWorkflowStates(teamId: team.id)
                    appState.workflowStates[team.id] = states.sorted { $0.position < $1.position }
                }
                await linearService.startPolling()
            } catch {
                print("[lnr] checkInitialState failed: \(error)")
                appState.connectionStatus = .error(message: error.localizedDescription)
            }
        }
    }
}
