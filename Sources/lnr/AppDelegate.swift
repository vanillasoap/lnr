import AppKit
import SwiftUI
import Combine
import os.log

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var appState: AppState!
    private var linearService: LinearService!
    private var cancellables = Set<AnyCancellable>()
    private var settingsController: SettingsWindowController?
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "app")

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()
        linearService = LinearService(appState: appState)
        settingsController = SettingsWindowController(appState: appState, linearService: linearService)

        applyAppearance()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.applyAppearance()
            }
        }
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
        button.action = #selector(togglePopover(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        let symbolName: String
        let badgeText: String?
        let toolTip: String

        switch appState.connectionStatus {
        case .notConfigured:
            symbolName = "smallcircle.filled.circle"
            badgeText = nil
            toolTip = "lnr — Not configured"
        case .connecting:
            symbolName = "arrow.trianglehead.2.clockwise.rotate.90.circle.fill"
            badgeText = nil
            toolTip = "lnr — Connecting..."
        case .connected:
            switch appState.syncStatus {
            case .syncing:
                symbolName = "smallcircle.filled.circle"
                badgeText = button.title.isEmpty ? nil : button.title
                toolTip = "lnr — Syncing..."
            case .failed:
                symbolName = "exclamationmark.circle"
                badgeText = button.title.isEmpty ? nil : button.title
                toolTip = "lnr — Last sync failed"
            case .idle:
                symbolName = "smallcircle.filled.circle"
                let count = appState.filteredIssues.count
                badgeText = (count > 0 && appState.showBadgeCount) ? "\(count)" : nil
                toolTip = count > 0 ? "lnr — \(count) issues" : "lnr — Connected"
            }
        case .error:
            symbolName = "exclamationmark.circle"
            badgeText = nil
            toolTip = "lnr — Last sync failed"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "lnr") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
        }
        button.title = badgeText ?? ""
        button.toolTip = toolTip
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

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Preferences…", action: #selector(openSettings), keyEquivalent: ",")
            menu.addItem(withTitle: "About lnr", action: #selector(showAbout), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit lnr", action: #selector(quitApp), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func openSettings() {
        settingsController?.showWindow()
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
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
                self.logger.error("[lnr] checkInitialState failed: \(String(describing: error), privacy: .public)")
                appState.connectionStatus = .error(message: error.localizedDescription)
            }
        }
    }
}
