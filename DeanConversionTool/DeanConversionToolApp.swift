import SwiftUI

/// Main application entry point
@main
struct DeanConversionToolApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            // Add custom menu commands
            CommandGroup(after: .newItem) {
                Button("Import Audio/Video...") {
                    NSApp.keyWindow?.contentView?.tryToPerform(
                        #selector(NSResponder.openDocument(_:)),
                        with: nil
                    )
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
