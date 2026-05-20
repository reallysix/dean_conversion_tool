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
    static let background        = Color(hex: 0xF2F2F3)
    static let workspace         = Color(hex: 0xFCFCFC)
    static let surface           = Color.white
    static let surfaceHover      = Color(hex: 0xF4F4F5)
    static let sidebarBackground = Color(hex: 0xFBFBFC)
    static let border            = Color(hex: 0xEFEFF1)
    static let textPrimary       = Color(hex: 0x1F1D23)
    static let textSecondary     = Color(hex: 0x6B6B6B)
    static let textTertiary      = Color(hex: 0xA8A8B0)
    static let accent            = Color(hex: 0x7B61FF)
    static let accentWarm        = Color(hex: 0xFFD238)
    static let accentBlue        = Color(hex: 0xDFF2FF)
    static let accentLilac       = Color(hex: 0xEFE7FF)
    static let accentSubtle      = Color(hex: 0x7B61FF).opacity(0.1)
    static let success           = Color(hex: 0x22A06B)
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
    static let cornerRadiusMedium: CGFloat = 8
    static let navRailWidth: CGFloat = 56
    static let historySidebarWidth: CGFloat = 230
    static let propertiesPanelWidth: CGFloat = 292
    static let bottomBarHeight: CGFloat = 64
}
