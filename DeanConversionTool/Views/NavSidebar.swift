import SwiftUI

enum SidePanel: String, CaseIterable {
    case transcript
    case settings
}

struct NavSidebar: View {
    @ObservedObject var viewModel: TranscriptViewModel
    @Binding var selectedPanel: SidePanel

    var body: some View {
        VStack(spacing: 0) {
            // App icon
            VStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(AppTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.accent.opacity(0.15))
                    .cornerRadius(AppTheme.cornerRadiusSmall)
            }
            .padding(.top, 16)
            .padding(.bottom, 24)

            // Nav items
            NavItem(icon: "doc.text", label: "转写", isSelected: selectedPanel == .transcript) {
                selectedPanel = .transcript
            }

            NavItem(icon: "gearshape", label: "设置", isSelected: selectedPanel == .settings) {
                selectedPanel = .settings
            }

            Spacer()
        }
        .frame(width: AppTheme.navRailWidth)
        .background(AppTheme.sidebarBackground)
    }
}

struct NavItem: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundColor(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                .frame(width: 34, height: 34)
                .background(isSelected ? AppTheme.accent.opacity(0.12) : Color.clear)
                .cornerRadius(AppTheme.cornerRadiusSmall)
            Text(label)
                .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? AppTheme.accent : AppTheme.textTertiary)
        }
        .frame(width: 48, height: 56)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .help(label)
    }
}
