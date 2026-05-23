import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.openSettings) private var openSettings
    @StateObject private var viewModel = TranscriptViewModel()
    @State private var isDragOver = false

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceSidebar(viewModel: viewModel) {
                openSettings()
            }

            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    TranscriptContainerView(viewModel: viewModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()

                    Rectangle()
                        .fill(AppTheme.border)
                        .frame(width: 1)

                    PropertiesPanel(viewModel: viewModel)
                        .frame(width: AppTheme.propertiesPanelWidth)
                }

                Rectangle()
                    .fill(AppTheme.border)
                    .frame(height: 1)
                BottomBar(viewModel: viewModel)
                    .frame(height: AppTheme.bottomBarHeight)
            }
        }
        .frame(minWidth: 1280, minHeight: 760)
        .background(AppTheme.workspace)
        .ignoresSafeArea(.container, edges: .top)
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
        .sheet(isPresented: $viewModel.showBatchSetup) {
            BatchSetupSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showBatchSummary) {
            BatchSummarySheet(viewModel: viewModel)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let supportedExtensions = ["mp3", "wav", "m4a", "aac", "flac", "ogg", "wma",
                                  "mp4", "mov", "avi", "mkv", "webm", "m4v"]
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      supportedExtensions.contains(url.pathExtension.lowercased()) else { return }
                urls.append(url)
            }
        }

        group.notify(queue: .main) {
            if urls.count == 1 {
                viewModel.processFile(url: urls[0])
            } else if urls.count > 1 {
                viewModel.batchQueue = urls
                viewModel.showBatchSetup = true
            }
        }

        return true
    }
}

// MARK: - Transcript Container

struct TranscriptContainerView: View {
    @ObservedObject var viewModel: TranscriptViewModel

    var body: some View {
        VStack(spacing: 0) {
            loadingAndErrorViews
            mediaPreview

            WorkspaceHeader(viewModel: viewModel)
            TranscriptToolbar(viewModel: viewModel)

            if viewModel.isLoading, viewModel.transcript == nil {
                ProcessingStateView(message: viewModel.loadingMessage, progress: viewModel.progress)
            } else if let transcript = viewModel.transcript {
                if viewModel.filteredSegments.isEmpty {
                    TranscriptEmptyStateView(searchText: viewModel.searchText)
                } else {
                    TranscriptView(viewModel: viewModel, selectionManager: viewModel.selectionManager, transcript: transcript)
                }
            } else if !viewModel.isLoading {
                WelcomeView(viewModel: viewModel)
            }
        }
    }

    @ViewBuilder
    private var loadingAndErrorViews: some View {
        if viewModel.isLoading {
            LoadingView(message: viewModel.loadingMessage, progress: viewModel.progress)
        }

        if let error = viewModel.error {
            if viewModel.canRetryOnlineVideo {
                ErrorBanner(message: error, retryTitle: "重试", onRetry: viewModel.retryOnlineVideo) {
                    viewModel.error = nil
                }
            } else {
                ErrorBanner(message: error) {
                    viewModel.error = nil
                }
            }
        }
    }

    @ViewBuilder
    private var mediaPreview: some View {
        if let player = viewModel.player, viewModel.isVideoFile {
            CompactVideoPlayerView(player: player)
                .frame(height: 260)
            Rectangle().fill(AppTheme.border).frame(height: 1)
        } else if let sourceURL = viewModel.transcript?.sourceURL, !sourceURL.isFileURL {
            if let player = viewModel.player {
                OnlineVideoPlayerPreview(sourceURL: sourceURL, player: player)
            } else {
                OnlineVideoEmbedView(
                    sourceURL: sourceURL,
                    seekTime: viewModel.playbackSeekTime,
                    seekRequestID: viewModel.playbackSeekRequestID,
                    isResolvingDirectPlayback: viewModel.isResolvingOnlinePreview,
                    previewError: viewModel.onlinePreviewError,
                    retryAction: { viewModel.loadOnlinePreview(for: sourceURL) }
                )
            }
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }
}

struct WorkspaceHeader: View {
    @ObservedObject var viewModel: TranscriptViewModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                titleBlock

                Spacer(minLength: 16)

                metrics
            }

            VStack(alignment: .leading, spacing: 12) {
                titleBlock
                metrics
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 12)
        .background(AppTheme.workspace)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.transcript?.displayTitle ?? "转写工作台")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textTertiary)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metrics: some View {
        HStack(spacing: 8) {
            HeaderMetric(title: "历史", value: "\(viewModel.historyProjects.count)")
            HeaderMetric(title: "片段", value: "\(viewModel.transcript?.segments.count ?? 0)")
            HeaderMetric(title: "说话人", value: "\(viewModel.transcript?.speakerCount ?? 0)")
        }
    }

    private var subtitle: String {
        if viewModel.isLoading {
            return viewModel.loadingMessage
        }
        if let transcript = viewModel.transcript {
            return "来源：\(transcript.displaySource)"
        }
        return "导入文件或粘贴链接开始转写，历史项目会自动归档"
    }
}

struct HeaderMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(width: 70, alignment: .leading)
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @ObservedObject var viewModel: TranscriptViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                WorkbenchHero()

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        actionPanels
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        actionPanels
                    }
                }

                RecentProjectsPreview(projects: Array(viewModel.historyProjects.prefix(3))) { project in
                    viewModel.openProject(project)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.workspace)
    }

    @ViewBuilder
    private var actionPanels: some View {
        ActionPanel(icon: "folder", title: "本地文件", subtitle: "音频、视频、批量文件") {
            VStack(spacing: 10) {
                PrimaryActionButton(icon: "plus", title: "导入本地文件", action: openFilePicker)
                SecondaryActionButton(icon: "square.stack.3d.up", title: "批量处理", action: openBatchPicker)
            }
        }

        ActionPanel(icon: "link", title: "在线视频", subtitle: "YouTube、B 站、抖音等公开链接") {
            VStack(spacing: 10) {
                let inputState = viewModel.onlineVideoInputState
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundColor(AppTheme.textTertiary)
                        .frame(width: 18)
                    TextField("https://...", text: $viewModel.onlineVideoURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(AppTheme.surfaceHover)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                        .stroke(AppTheme.border)
                )
                .cornerRadius(AppTheme.cornerRadiusMedium)

                HStack(spacing: 6) {
                    Circle()
                        .fill(inputState.isReady ? AppTheme.success : AppTheme.textTertiary.opacity(0.6))
                        .frame(width: 6, height: 6)
                    Text(inputState.message)
                        .font(.system(size: 10))
                        .foregroundColor(inputState.isReady ? AppTheme.success : AppTheme.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                PrimaryActionButton(icon: "arrow.down.circle", title: "解析并转写") {
                    viewModel.processOnlineVideo(urlString: inputState.normalizedURLString ?? viewModel.onlineVideoURL)
                }
                .disabled(!inputState.isReady)
                .opacity(inputState.isReady ? 1 : 0.45)
            }
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "选择音频或视频文件"
        panel.allowedContentTypes = [
            .audio, .mp3, .wav, .aiff, .mpeg4Audio,
            .movie, .mpeg4Movie, .quickTimeMovie
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.processFile(url: url)
        }
    }

    private func openBatchPicker() {
        let panel = NSOpenPanel()
        panel.title = "选择多个音频或视频文件"
        panel.allowedContentTypes = [
            .audio, .mp3, .wav, .aiff, .mpeg4Audio,
            .movie, .mpeg4Movie, .quickTimeMovie
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, !panel.urls.isEmpty {
            viewModel.batchQueue = panel.urls
            viewModel.showBatchSetup = true
        }
    }
}

struct ProcessingStateView: View {
    let message: String
    let progress: Double

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(AppTheme.surfaceHover, lineWidth: 10)
                    .frame(width: 118, height: 118)
                Circle()
                    .trim(from: 0, to: max(0.02, min(progress, 1)))
                    .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 118, height: 118)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppTheme.textPrimary)
            }

            VStack(spacing: 6) {
                Text(message.isEmpty ? "正在处理素材" : message)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("完成后会自动保存到历史记录。")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.workspace)
    }
}

struct TranscriptEmptyStateView: View {
    let searchText: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 34, weight: .medium))
                .foregroundColor(AppTheme.textTertiary)
                .frame(width: 74, height: 74)
                .background(AppTheme.surface)
                .cornerRadius(AppTheme.cornerRadiusMedium)

            Text(searchText.isEmpty ? "暂无可显示片段" : "没有匹配的文稿片段")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
            Text(searchText.isEmpty ? "转写完成后，片段会显示在这里。" : "换个关键词再试试。")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.workspace)
    }
}

struct WorkbenchHero: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 24) {
                copyBlock
                Spacer(minLength: 10)
                heroMark
            }

            VStack(alignment: .leading, spacing: 18) {
                copyBlock
                heroMark
            }
        }
        .padding(22)
        .frame(minHeight: 154)
        .background(AppTheme.surface)
        .cornerRadius(AppTheme.cornerRadiusMedium)
    }

    private var copyBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppTheme.accentWarm)
                    .frame(width: 8, height: 8)
                Text("Ready to transcribe")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
            }

            Text("把素材变成可编辑文稿")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("本地视频、音频和在线视频链接都从这里开始，完成后自动进入历史归档。")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var heroMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.accentLilac)
                .frame(width: 146, height: 118)
            Circle()
                .fill(AppTheme.accentWarm)
                .frame(width: 16, height: 16)
                .offset(x: -56, y: -34)
            Circle()
                .fill(AppTheme.accent)
                .frame(width: 13, height: 13)
                .offset(x: 58, y: 34)
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(AppTheme.textPrimary)
        }
    }
}

struct ActionPanel<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.accentWarm.opacity(0.5))
                    .cornerRadius(AppTheme.cornerRadiusSmall)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppTheme.surface)
        .cornerRadius(AppTheme.cornerRadiusMedium)
    }
}

struct RecentProjectsPreview: View {
    let projects: [HistoryProject]
    let onOpen: (HistoryProject) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近项目")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)

            if projects.isEmpty {
                Text("完成第一条转写后，这里会显示最近处理过的项目。")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(projects) { project in
                    Button(action: { onOpen(project) }) {
                        HStack(spacing: 10) {
                            Image(systemName: project.sourceType == .onlineVideo ? "link" : "doc.text")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                                .frame(width: 30, height: 30)
                                .background(project.sourceType == .onlineVideo ? AppTheme.accentWarm.opacity(0.55) : AppTheme.accentBlue)
                                .cornerRadius(AppTheme.cornerRadiusSmall)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppTheme.textPrimary)
                                    .lineLimit(1)
                                Text(project.sourceType.displayName)
                                    .font(.system(size: 10))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(AppTheme.surface)
        .cornerRadius(AppTheme.cornerRadiusMedium)
    }
}

struct PrimaryActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(AppTheme.textPrimary)
            .cornerRadius(AppTheme.cornerRadiusMedium)
        }
        .buttonStyle(WorkbenchPlainButtonStyle())
    }
}

struct SecondaryActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
            }
            .foregroundColor(AppTheme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(AppTheme.surfaceHover)
            .cornerRadius(AppTheme.cornerRadiusMedium)
        }
        .buttonStyle(WorkbenchPlainButtonStyle())
    }
}

// MARK: - Loading View

struct LoadingView: View {
    let message: String
    let progress: Double

    var body: some View {
        VStack(spacing: 10) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(AppTheme.accent)

            HStack {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.surface)
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    var retryTitle: String?
    var onRetry: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.danger)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.danger)
            Spacer()
            if let retryTitle, let onRetry {
                Button(action: onRetry) {
                    Text(retryTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.danger)
                }
                .buttonStyle(.plain)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.danger.opacity(0.1))
    }
}

#Preview {
    ContentView()
}
