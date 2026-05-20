import SwiftUI

struct PropertiesPanel: View {
    @ObservedObject var viewModel: TranscriptViewModel
    private let exportService = ExportService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(viewModel.transcript == nil ? "任务状态" : "文稿详情")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(.top, 24)

                if let transcript = viewModel.transcript {
                    PropertiesSection(title: "文件") {
                        PropertyRow(label: "名称", value: transcript.displayTitle)
                        PropertyRow(label: "来源", value: transcript.sourceURL.isFileURL ? "本地文件" : "在线视频")
                        PropertyRow(label: "时长", value: formatDuration(transcript.duration))
                        PropertyRow(label: "片段", value: "\(transcript.segments.count)")
                        PropertyRow(label: "语言", value: transcript.language ?? "自动")
                    }

                    PropertiesSection(title: "说话人") {
                        ForEach(transcript.speakers, id: \.self) { speaker in
                            let count = transcript.segments.filter { $0.speaker == speaker }.count
                            SpeakerRow(speaker: speaker, segmentCount: count)
                        }
                    }

                    PropertiesSection(title: "选择") {
                        HStack(spacing: 8) {
                            PropertyButton(title: "全选") { viewModel.selectAllSegments() }
                            PropertyButton(title: "取消") { viewModel.deselectAllSegments() }
                        }
                        if !viewModel.selectionManager.selectedIDs.isEmpty {
                            PropertyButton(title: "复制选中 (\(viewModel.selectionManager.selectedIDs.count))") {
                                viewModel.copySelectedSegments()
                            }
                        }
                    }

                    PropertiesSection(title: "导出") {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            PropertyButton(title: exportService.formatDisplayName(for: format)) {
                                viewModel.exportTranscript(format: format)
                            }
                        }
                    }
                } else {
                    EmptyPropertiesPanel(viewModel: viewModel)
                }

                Spacer()
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 24)
        }
        .background(AppTheme.surface)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Helper Views

struct PropertiesSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.textTertiary)
                .textCase(.uppercase)
            content
        }
        .padding(14)
        .background(AppTheme.surfaceHover)
        .cornerRadius(AppTheme.cornerRadiusMedium)
    }
}

struct EmptyPropertiesPanel: View {
    @ObservedObject var viewModel: TranscriptViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatusBubble(icon: "folder", title: "本地导入", message: "选择音频或视频文件后自动转写。")
            StatusBubble(icon: "link", title: "在线链接", message: "粘贴公开视频链接后会先解析音频。")
            StatusBubble(icon: "archivebox", title: "历史归档", message: "结果会按视频标题保存，方便回看。")

            Divider()
                .background(AppTheme.border)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text("环境")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                MiniStatus(label: "Whisper", available: viewModel.isWhisperCLIAvailable)
                MiniStatus(label: "模型", available: viewModel.isWhisperModelAvailable)
                MiniStatus(label: "FFmpeg", available: viewModel.isFFmpegAvailable)
                MiniStatus(label: "yt-dlp", available: viewModel.isYTDLPAvailable)
            }
        }
    }
}

struct StatusBubble: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
                .frame(width: 32, height: 32)
                .background(AppTheme.accentLilac)
                .cornerRadius(AppTheme.cornerRadiusSmall)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(AppTheme.surfaceHover)
        .cornerRadius(AppTheme.cornerRadiusMedium)
    }
}

struct MiniStatus: View {
    let label: String
    let available: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(available ? AppTheme.success : AppTheme.danger)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(available ? "就绪" : "缺失")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(available ? AppTheme.success : AppTheme.danger)
        }
    }
}

struct PropertyRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1)
        }
    }
}

struct PropertyButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(AppTheme.surface)
                .cornerRadius(AppTheme.cornerRadiusSmall)
        }
        .buttonStyle(.plain)
    }
}

struct SpeakerRow: View {
    let speaker: String
    let segmentCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(speakerColor)
                .frame(width: 8, height: 8)
            Text(speaker)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textPrimary)
            Spacer()
            Text("\(segmentCount)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
        }
    }

    private var speakerColor: Color {
        let hash = abs(speaker.hashValue)
        return AppTheme.speakerColors[hash % AppTheme.speakerColors.count]
    }
}
