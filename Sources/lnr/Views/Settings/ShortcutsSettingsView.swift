import SwiftUI

struct ShortcutsSettingsView: View {
    private let shortcuts: [(String, String)] = [
        ("⌘O", "Open in Linear"), ("⌘L", "Copy link"), ("⌘.", "Copy identifier"),
        ("⌘⌫", "Delete issue"), ("⌘K", "Focus search"),
        ("↑↓", "Navigate issues"), ("↩", "Open selected issue"), ("Space", "Expand / collapse"),
    ]
    var body: some View {
        Form {
            Section("Keyboard Shortcuts") {
                ForEach(shortcuts, id: \.0) { shortcut, action in
                    HStack {
                        Text(shortcut).font(.body.monospaced()).frame(width: 60, alignment: .trailing)
                        Text(action).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
