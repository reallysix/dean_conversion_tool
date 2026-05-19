import SwiftUI

// MARK: - Color(hex:) Extension

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - App Theme (Light Style)

struct AppTheme {
    // MARK: - Colors
    static let background        = Color(hex: 0xF8F8F8)
    static let surface           = Color.white
    static let surfaceHover      = Color(hex: 0xF0F0F0)
    static let sidebarBackground = Color(hex: 0xEFEFEF)
    static let border            = Color(hex: 0xE0E0E0)
    static let textPrimary       = Color(hex: 0x1A1A1A)
    static let textSecondary     = Color(hex: 0x6B6B6B)
    static let textTertiary      = Color(hex: 0x9B9B9B)
    static let accent            = Color(hex: 0x007AFF)
    static let accentSubtle      = Color(hex: 0x007AFF).opacity(0.08)
    static let danger            = Color(hex: 0xE53E3E)

    // MARK: - Speaker Colors
    static let speakerColors: [Color] = [
        Color(hex: 0x007AFF),  // blue
        Color(hex: 0x34C759),  // green
        Color(hex: 0xFF9500),  // orange
        Color(hex: 0xAF52DE),  // purple
        Color(hex: 0xFF2D55),  // pink
        Color(hex: 0x5AC8FA),  // teal
    ]

    // MARK: - Spacing
    static let cornerRadiusSmall: CGFloat = 6
    static let cornerRadiusMedium: CGFloat = 10
    static let navRailWidth: CGFloat = 56
    static let propertiesPanelWidth: CGFloat = 260
    static let bottomBarHeight: CGFloat = 72
}
