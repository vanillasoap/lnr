import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Picker("Refresh interval", selection: $appState.pollingInterval) {
                Text("30s").tag(TimeInterval(30))
                Text("60s").tag(TimeInterval(60))
                Text("2m").tag(TimeInterval(120))
                Text("5m").tag(TimeInterval(300))
                Text("10m").tag(TimeInterval(600))
            }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch { launchAtLogin = !newValue }
                }
            Toggle("Show badge count on icon", isOn: $appState.showBadgeCount)
            Picker("Appearance", selection: Binding(
                get: { UserDefaults.standard.string(forKey: Constants.Defaults.appearanceMode) ?? "system" },
                set: { newValue in
                    UserDefaults.standard.set(newValue, forKey: Constants.Defaults.appearanceMode)
                    switch newValue {
                    case "light": NSApp.appearance = NSAppearance(named: .aqua)
                    case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
                    default: NSApp.appearance = nil
                    }
                }
            )) {
                Text("Light").tag("light")
                Text("Dark").tag("dark")
                Text("System").tag("system")
            }
            .pickerStyle(.segmented)
            Picker("Open issues in", selection: Binding(
                get: { UserDefaults.standard.string(forKey: Constants.Defaults.openIssuesIn) ?? "browser" },
                set: { UserDefaults.standard.set($0, forKey: Constants.Defaults.openIssuesIn) }
            )) {
                Text("Default browser").tag("browser")
                Text("Linear desktop app").tag("linear")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
