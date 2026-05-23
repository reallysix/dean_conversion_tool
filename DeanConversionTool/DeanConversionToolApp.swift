import SwiftUI
import AppKit

/// Main application entry point
@main
struct DeanConversionToolApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 860)
        .commands {
            // Add custom menu commands
            CommandGroup(after: .newItem) {
                Button("导入音频/视频...") {
                    // Open file dialog will be handled by the view
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.minSize = NSSize(width: 1280, height: 760)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
