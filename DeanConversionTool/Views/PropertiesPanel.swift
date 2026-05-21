import SwiftUI

struct PropertiesPanel: View {
    @ObservedObject var viewModel: TranscriptViewModel
    private let exportService = ExportService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("任务状态")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .padding(.top, 24)

                if let transcript = viewModel.transcript {
                    TaskStatusSummaryView(viewModel: viewModel, transcript: transcript)

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
                        if let message = viewModel.exportStatusMessage {
                            ExportStatusView(
                                message: message,
                                isError: viewModel.exportStatusIsError,
                                fileURL: viewModel.lastExportedFileURL,
                                revealAction: viewModel.revealLastExportedFile
                            )
                        }
                    }

                    PropertiesSection(title: "环境") {
                        EnvironmentStatusPanel(viewModel: viewModel, compact: true)
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
            PropertiesSection(title: "开始") {
                StatusBubble(icon: "folder", title: "本地导入", message: "选择音频或视频文件后自动转写。")
                StatusBubble(icon: "link", title: "在线链接", message: "粘贴公开视频链接后会先解析音频。")
                StatusBubble(icon: "archivebox", title: "历史归档", message: "结果会按视频标题保存，方便回看。")
            }

            PropertiesSection(title: "环境") {
                EnvironmentStatusPanel(viewModel: viewModel)
            }
        }
    }
}

struct TaskStatusSummaryView: View {
    @ObservedObject var viewModel: TranscriptViewModel
    let transcript: Transcript

    var body: some View {
        PropertiesSection(title: "当前") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: transcript.sourceURL.isFileURL ? "doc.text" : "link")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(transcript.sourceURL.isFileURL ? AppTheme.accentBlue : AppTheme.accentWarm.opacity(0.45))
                        .cornerRadius(AppTheme.cornerRadiusSmall)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.isLoading ? "正在处理" : "已完成")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(viewModel.isLoading ? AppTheme.accent : AppTheme.success)
                        Text(transcript.sourceURL.isFileURL ? "本地文件转写" : "在线视频转写")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    Spacer(minLength: 0)
                }

                if viewModel.isLoading {
                    ProgressView(value: viewModel.progress)
                        .progressViewStyle(.linear)
                        .tint(AppTheme.accent)
                    Text(viewModel.loadingMessage)
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                        .lineLimit(2)
                } else {
                    Text("文稿、字幕和文本文件已进入历史归档。")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct EnvironmentStatusPanel: View {
    @ObservedObject var viewModel: TranscriptViewModel
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !compact {
                EnvironmentSummary(
                    missingRequired: viewModel.requiredSetupMissingCount,
                    missingOptional: viewModel.optionalSetupMissingCount
                )
            }

            ForEach(viewModel.setupStatusItems) { item in
                EnvironmentStatusRow(
                    item: item,
                    isInstalling: viewModel.isInstallingDependencies,
                    installAction: viewModel.installMissingDependencies
                )
            }

            if compact, viewModel.requiredSetupMissingCount == 0, viewModel.optionalSetupMissingCount == 0 {
                Text("核心环境已就绪")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(AppTheme.success)
            }

            if viewModel.isDownloadingModel {
                ModelDownloadProgressView(viewModel: viewModel)
            } else if !viewModel.isWhisperModelAvailable {
                ModelDownloadPrompt(viewModel: viewModel)
            } else if !viewModel.modelDownloadMessage.isEmpty {
                Text(viewModel.modelDownloadMessage)
                    .font(.system(size: 11))
                    .foregroundColor(viewModel.modelDownloadIsError ? AppTheme.danger : AppTheme.success)
                    .padding(.top, 2)
            }

            if viewModel.requiredSetupMissingCount > 0 {
                Button(action: viewModel.copyDependencyCheckCommand) {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal")
                            .font(.system(size: 10, weight: .semibold))
                        Text("复制一键检查命令")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(AppTheme.textPrimary)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }

            if let message = viewModel.dependencyInstallMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundColor(viewModel.dependencyInstallIsError ? AppTheme.danger : AppTheme.success)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            if let message = viewModel.setupClipboardMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.success)
                    .lineLimit(2)
            }
        }
    }
}

struct ModelDownloadProgressView: View {
    @ObservedObject var viewModel: TranscriptViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                ProgressView(value: viewModel.modelDownloadProgress)
                    .progressViewStyle(.linear)
                Text("\(Int(viewModel.modelDownloadProgress * 100))%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(width: 34, alignment: .trailing)
                Button(action: viewModel.cancelModelDownload) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("取消下载")
            }

            Text(viewModel.modelDownloadMessage)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textTertiary)
                .lineLimit(2)
        }
        .padding(.top, 4)
    }
}

struct ModelDownloadPrompt: View {
    @ObservedObject var viewModel: TranscriptViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(viewModel.whisperModelName) · \(viewModel.whisperModelSizeDescription)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Text("用于本地离线转写。下载后保存到：\(viewModel.whisperModelDirectory)")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
                    .lineLimit(3)
            }

            if !viewModel.modelDownloadMessage.isEmpty {
                Text(viewModel.modelDownloadMessage)
                    .font(.system(size: 10))
                    .foregroundColor(viewModel.modelDownloadIsError ? AppTheme.danger : AppTheme.textTertiary)
                    .lineLimit(3)
            }

            HStack(spacing: 10) {
                Button(action: viewModel.downloadWhisperModel) {
                    Text(viewModel.modelDownloadIsError ? "重试下载" : "下载模型")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                }
                .buttonStyle(.plain)

                Button(action: viewModel.openModelDirectory) {
                    Text("打开目录")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                }
                .buttonStyle(.plain)

                Button(action: viewModel.openModelDownloadPage) {
                    Text("下载源")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }
}

struct EnvironmentSummary: View {
    let missingRequired: Int
    let missingOptional: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(missingRequired == 0 ? AppTheme.success : AppTheme.danger)
            Text(message)
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)
    }

    private var title: String {
        if missingRequired == 0 {
            return "核心环境已就绪"
        }
        return "还缺 \(missingRequired) 项核心依赖"
    }

    private var message: String {
        if missingRequired > 0 {
            return "先补齐核心依赖，再导入本地文件或在线视频。"
        }
        if missingOptional > 0 {
            return "可选能力缺失不影响基础转写。"
        }
        return "本地转写和在线视频解析都可以开始使用。"
    }
}

struct EnvironmentStatusRow: View {
    let item: TranscriptViewModel.SetupStatusItem
    let isInstalling: Bool
    let installAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)
                    Text(item.isRequired ? "必需" : "可选")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(item.isRequired ? AppTheme.textPrimary : AppTheme.textTertiary)
                }
                Text(item.isAvailable ? "已检测到" : item.detail)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
                    .lineLimit(2)

                if !item.isAvailable, let command = item.installCommand {
                    Button(action: installAction) {
                        HStack(spacing: 4) {
                            Image(systemName: isInstalling ? "hourglass" : "arrow.down.circle")
                                .font(.system(size: 9, weight: .semibold))
                            Text(isInstalling ? "安装中..." : "点击安装")
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(isInstalling)
                    .help(command)
                }
            }
            Spacer(minLength: 4)
            Text(statusText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(statusColor)
        }
    }

    private var statusText: String {
        if item.isAvailable {
            return "就绪"
        }
        return item.isRequired ? "缺失" : "建议"
    }

    private var statusColor: Color {
        if item.isAvailable {
            return AppTheme.success
        }
        return item.isRequired ? AppTheme.danger : AppTheme.accentWarm
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
        .padding(.vertical, 4)
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

struct ExportStatusView: View {
    let message: String
    let isError: Bool
    let fileURL: URL?
    let revealAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Circle()
                    .fill(isError ? AppTheme.danger : AppTheme.success)
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isError ? AppTheme.danger : AppTheme.success)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let fileURL {
                Text(fileURL.deletingLastPathComponent().path)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                PropertyButton(title: "在访达中显示") {
                    revealAction()
                }
            }
        }
        .padding(.top, 4)
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
