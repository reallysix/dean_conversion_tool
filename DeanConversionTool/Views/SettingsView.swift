import SwiftUI

/// Settings view for configuring the application
struct SettingsView: View {
    @AppStorage("defaultLanguage") private var defaultLanguage = "auto"
    @AppStorage("enableSpeakerDiarization") private var enableSpeakerDiarization = true
    @State private var selectedTab = 0

    private let tabs = [
        (icon: "gear", label: "通用"),
        (icon: "slider.horizontal.3", label: "功能"),
        (icon: "info.circle", label: "关于"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    Button(action: { selectedTab = index }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12))
                            Text(tab.label)
                                .font(.system(size: 13, weight: selectedTab == index ? .semibold : .regular))
                        }
                        .foregroundColor(selectedTab == index ? AppTheme.accent : AppTheme.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(selectedTab == index ? AppTheme.accent.opacity(0.08) : Color.clear)
                        .cornerRadius(AppTheme.cornerRadiusSmall)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            // Tab content
            Group {
                switch selectedTab {
                case 0:
                    GeneralSettingsView(
                        defaultLanguage: $defaultLanguage
                    )
                case 1:
                    FeatureSettingsView(
                        enableSpeakerDiarization: $enableSpeakerDiarization
                    )
                case 2:
                    AboutSettingsView()
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// General settings
struct GeneralSettingsView: View {
    @Binding var defaultLanguage: String

    let languages = [
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
        Form {
            Section("转写设置") {
                Picker("默认语言", selection: $defaultLanguage) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }

                LabeledContent("Whisper 模型") {
                    Text("Large V3 (~3.1GB)")
                        .foregroundColor(AppTheme.textSecondary)
                }

                Text("当前版本固定使用 large-v3。后续会再开放多模型切换。")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding()
    }
}

/// Feature settings
struct FeatureSettingsView: View {
    @Binding var enableSpeakerDiarization: Bool

    var body: some View {
        Form {
            Section("功能开关") {
                Toggle("启用说话人识别", isOn: $enableSpeakerDiarization)
                    .help("识别音频中的不同说话人")

                if enableSpeakerDiarization {
                    Text("需要安装 Python 及 pyannote.audio")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textSecondary)
                        .padding(.leading, 20)
                }
            }

            Section("导出设置") {
                Toggle("导出时包含时间戳", isOn: .constant(true))
                Toggle("导出时包含说话人标签", isOn: .constant(true))
            }
        }
        .padding()
    }
}

/// About settings
struct AboutSettingsView: View {
    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("语音转文字工具")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Text("版本 1.0.0")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("• Whisper.cpp（本地 AI 语音转写）")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("• pyannote.audio（说话人识别）")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textPrimary)
                }

                Spacer()

                Text("基于 SwiftUI 构建，适用于 macOS")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding()
    }
}

#Preview {
    SettingsView()
}
