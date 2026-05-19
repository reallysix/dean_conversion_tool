import SwiftUI

struct PropertiesPanel: View {
    @ObservedObject var viewModel: TranscriptViewModel
    private let exportService = ExportService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("属性")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                if let transcript = viewModel.transcript {
                    // File info
                    PropertiesSection(title: "文件") {
                        PropertyRow(label: "名称", value: transcript.sourceURL.lastPathComponent)
                        PropertyRow(label: "时长", value: formatDuration(transcript.duration))
                        PropertyRow(label: "片段", value: "\(transcript.segments.count)")
                        PropertyRow(label: "语言", value: transcript.language ?? "自动")
                    }

                    Divider().background(AppTheme.border).padding(.vertical, 10)

                    // Speakers
                    PropertiesSection(title: "说话人") {
                        ForEach(transcript.speakers, id: \.self) { speaker in
                            let count = transcript.segments.filter { $0.speaker == speaker }.count
                            SpeakerRow(speaker: speaker, segmentCount: count)
                        }
                    }

                    Divider().background(AppTheme.border).padding(.vertical, 10)

                    // Selection
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

                    Divider().background(AppTheme.border).padding(.vertical, 10)

                    // Export
                    PropertiesSection(title: "导出") {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            PropertyButton(title: exportService.formatDisplayName(for: format)) {
                                viewModel.exportTranscript(format: format)
                            }
                        }
                    }
                } else {
                    Text("导入文件后查看属性")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                        .padding(16)
                }

                Spacer()
            }
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
        .padding(.horizontal, 16)
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
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(AppTheme.surfaceHover)
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
