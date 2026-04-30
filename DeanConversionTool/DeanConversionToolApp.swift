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
                    // Open file dialog will be handled by the view
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
