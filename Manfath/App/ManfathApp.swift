import SwiftUI

@main
struct ManfathApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // AppKit owns the actual Settings window.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("menu.preferences") { appDelegate.openSettings(nil) }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}
