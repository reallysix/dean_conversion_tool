import SwiftUI
import AppKit

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
                Button("导入音频/视频...") {
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
