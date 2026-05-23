import SwiftUI

/// Settings view for configuring the application.
struct SettingsView: View {
    @AppStorage("defaultLanguage") private var defaultLanguage = "auto"
    @AppStorage("enableSpeakerDiarization") private var enableSpeakerDiarization = true
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    SettingsHeader(section: selectedSection)

                    switch selectedSection {
                    case .general:
                        GeneralSettingsPanel(defaultLanguage: $defaultLanguage)
                    case .model:
                        ModelSettingsPanel()
                    case .features:
                        FeatureSettingsPanel(enableSpeakerDiarization: $enableSpeakerDiarization)
                    case .about:
                        AboutSettingsPanel()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 44)
                .padding(.top, 42)
                .padding(.bottom, 40)
            }
            .background(AppTheme.workspace)
        }
        .frame(width: 920, height: 620)
        .background(AppTheme.workspace)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(SettingsSection.allCases) { section in
                SettingsSidebarRow(
                    section: section,
                    isSelected: selectedSection == section
                ) {
                    selectedSection = section
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 28)
        .frame(width: 210)
        .background(AppTheme.sidebarBackground)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case model
    case features
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .model: return "模型"
        case .features: return "功能"
        case .about: return "关于"
        }
    }

    var headline: String {
        switch self {
        case .general: return "通用设置"
        case .model: return "模型设置"
        case .features: return "功能设置"
        case .about: return "关于 Deanly"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "调整默认转写行为和项目保存位置。"
        case .model: return "查看当前 Whisper 模型与本地推理策略。"
        case .features: return "管理说话人识别、导出内容等可选能力。"
        case .about: return "查看应用版本和核心开源组件。"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .model: return "cpu"
        case .features: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
}

private struct SettingsSidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 17))
                    .frame(width: 22)
                Text(section.title)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                Spacer()
                if !isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary.opacity(0.65))
                }
            }
            .foregroundColor(isSelected ? AppTheme.textPrimary : AppTheme.textSecondary)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 48)
            .background(isSelected ? AppTheme.surfaceHover : Color.clear)
            .cornerRadius(AppTheme.cornerRadiusMedium)
            .contentShape(Rectangle())
        }
        .buttonStyle(WorkbenchPlainButtonStyle())
    }
}

private struct SettingsHeader: View {
    let section: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.headline)
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)

            Text(section.subtitle)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textTertiary)
        }
    }
}

private struct GeneralSettingsPanel: View {
    @Binding var defaultLanguage: String

    private let languages = [
        ("auto", "自动检测"),
        ("zh", "中文"),
        ("en", "英语"),
        ("ja", "日语"),
        ("ko", "韩语"),
        ("es", "西班牙语"),
        ("fr", "法语"),
        ("de", "德语")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsHeroCard(
                icon: "folder",
                title: "历史归档目录",
                subtitle: "转写项目、字幕和文本文件会自动保存在这里。",
                value: "~/Documents/DeanConversionTool/Projects"
            )

            SettingsSectionGroup(title: "转写") {
                SettingsRow(title: "默认语言", subtitle: "选择自动检测，或固定为常用语言。") {
                    Picker("", selection: $defaultLanguage) {
                        ForEach(languages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                SettingsRow(title: "历史归档", subtitle: "完成转写后自动保存项目记录和导出文件。") {
                    StatusPill(text: "已开启", color: AppTheme.success)
                }
            }
        }
    }
}

private struct ModelSettingsPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsHeroCard(
                icon: "waveform",
                title: "Whisper large-v3",
                subtitle: "当前版本固定使用本地 large-v3 模型，优先保证转写质量。",
                value: "~/Library/Application Support/DeanConversion/models"
            )

            SettingsSectionGroup(title: "模型") {
                SettingsRow(title: "推理方式", subtitle: "通过 whisper.cpp 在本机完成转写。") {
                    StatusPill(text: "本地", color: AppTheme.accent)
                }

                SettingsRow(title: "模型切换", subtitle: "多模型切换会在后续版本开放。") {
                    StatusPill(text: "计划中", color: AppTheme.textTertiary)
                }
            }
        }
    }
}

private struct FeatureSettingsPanel: View {
    @Binding var enableSpeakerDiarization: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionGroup(title: "说话人识别") {
                SettingsRow(title: "启用说话人识别", subtitle: "识别音频中的不同说话人，可选依赖 pyannote.audio。") {
                    Toggle("", isOn: $enableSpeakerDiarization)
                        .labelsHidden()
                }

                if enableSpeakerDiarization {
                    SettingsNotice(
                        icon: "exclamationmark.circle",
                        text: "该能力需要 Python、pyannote.audio 和 Hugging Face 模型授权。缺失时不影响基础转写。"
                    )
                }
            }

            SettingsSectionGroup(title: "导出") {
                SettingsRow(title: "时间戳", subtitle: "导出文稿时保留片段时间信息。") {
                    StatusPill(text: "已开启", color: AppTheme.success)
                }

                SettingsRow(title: "说话人标签", subtitle: "有识别结果时导出说话人标签。") {
                    StatusPill(text: "已开启", color: AppTheme.success)
                }
            }
        }
    }
}

private struct AboutSettingsPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsHeroCard(
                icon: "sparkles",
                title: "Deanly",
                subtitle: "macOS 原生音视频转文字工具。",
                value: "版本 1.0.0"
            )

            SettingsSectionGroup(title: "核心组件") {
                SettingsRow(title: "whisper.cpp", subtitle: "本地 AI 语音转写。") {
                    StatusPill(text: "核心", color: AppTheme.accent)
                }

                SettingsRow(title: "FFmpeg", subtitle: "音视频预处理。") {
                    StatusPill(text: "必需", color: AppTheme.success)
                }

                SettingsRow(title: "yt-dlp", subtitle: "公开视频链接解析。") {
                    StatusPill(text: "必需", color: AppTheme.success)
                }
            }
        }
    }
}

private struct SettingsHeroCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .frame(width: 46, height: 46)
                    .background(AppTheme.accentWarm.opacity(0.65))
                    .cornerRadius(AppTheme.cornerRadiusMedium)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundColor(AppTheme.textSecondary)
                Text(value)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(AppTheme.surface)
            .cornerRadius(AppTheme.cornerRadiusSmall)
        }
        .padding(22)
        .background(AppTheme.surfaceHover)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                .stroke(AppTheme.border, lineWidth: 1)
        )
        .cornerRadius(AppTheme.cornerRadiusMedium)
    }
}

private struct SettingsSectionGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)

            VStack(spacing: 0) {
                content
            }
            .background(AppTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .cornerRadius(AppTheme.cornerRadiusMedium)
        }
    }
}

private struct SettingsRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 20)

            trailing
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)
                .padding(.leading, 18)
        }
    }
}

private struct SettingsNotice: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(AppTheme.surfaceHover)
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(color.opacity(0.11))
            .cornerRadius(AppTheme.cornerRadiusSmall)
    }
}

#Preview {
    SettingsView()
}
