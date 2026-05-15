import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let appState: AppState
    private let linearService: LinearService

    init(appState: AppState, linearService: LinearService) {
        self.appState = appState
        self.linearService = linearService
    }

    func showWindow() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let settingsView = SettingsTabView()
            .environmentObject(appState)
            .environment(\.linearService, linearService)
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "lnr Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: Constants.settingsWidth, height: Constants.settingsHeight))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

struct SettingsTabView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AccountSettingsView()
                .tabItem { Label("Account", systemImage: "person") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "square.grid.2x2") }
        }
        .frame(width: Constants.settingsWidth, height: Constants.settingsHeight)
    }
}
