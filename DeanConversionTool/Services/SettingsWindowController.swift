import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show(relativeTo parentWindow: NSWindow?) {
        let settingsWindow = window ?? makeWindow()
        window = settingsWindow

        position(settingsWindow, relativeTo: parentWindow)

        if settingsWindow.parent !== parentWindow {
            settingsWindow.parent?.removeChildWindow(settingsWindow)
        }

        if let parentWindow {
            parentWindow.addChildWindow(settingsWindow, ordered: .above)
        }

        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let hostingView = NSHostingView(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 520)
        return window
    }

    private func position(_ settingsWindow: NSWindow, relativeTo parentWindow: NSWindow?) {
        guard let parentWindow else {
            settingsWindow.center()
            return
        }

        let parentFrame = parentWindow.frame
        let windowSize = settingsWindow.frame.size
        let targetScreen = parentWindow.screen ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? parentFrame

        var origin = NSPoint(
            x: parentFrame.midX - windowSize.width / 2,
            y: parentFrame.midY - windowSize.height / 2
        )

        origin.x = min(max(origin.x, visibleFrame.minX + 16), visibleFrame.maxX - windowSize.width - 16)
        origin.y = min(max(origin.y, visibleFrame.minY + 16), visibleFrame.maxY - windowSize.height - 16)

        settingsWindow.setFrameOrigin(origin)
    }
}
