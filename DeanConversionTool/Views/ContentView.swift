import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = TranscriptViewModel()
    @State private var isDragOver = false
    @State private var selectedPanel: SidePanel = .transcript

    var body: some View {
        HStack(spacing: 0) {
            // Left workspace rail
            WorkspaceSidebar(viewModel: viewModel, selectedPanel: $selectedPanel)

            Rectangle()
                .fill(AppTheme.border)
                .frame(width: 1)

            // Center + Right stacked
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Center content - both views always present, toggle opacity
                    ZStack {
                        TranscriptContainerView(viewModel: viewModel)
                            .opacity(selectedPanel == .transcript ? 1 : 0)
                            .allowsHitTesting(selectedPanel == .transcript)

                        EmbeddedSettingsView()
                            .opacity(selectedPanel == .settings ? 1 : 0)
                            .allowsHitTesting(selectedPanel == .settings)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                    Rectangle()
                        .fill(AppTheme.border)
                        .frame(width: 1)

                    // Right properties panel
                    PropertiesPanel(viewModel: viewModel)
                        .frame(width: AppTheme.propertiesPanelWidth)
                }

                // Bottom bar
                Rectangle()
                    .fill(AppTheme.border)
                    .frame(height: 1)
                BottomBar(viewModel: viewModel)
                    .frame(height: AppTheme.bottomBarHeight)
            }
        }
        .frame(minWidth: 1100, minHeight: 680)
        .background(AppTheme.background)
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
            if viewModel.isLoading {
                LoadingView(message: viewModel.loadingMessage, progress: viewModel.progress)
            }

            if let error = viewModel.error {
                ErrorBanner(message: error) { viewModel.error = nil }
            }

            if let player = viewModel.player, viewModel.isVideoFile {
                CompactVideoPlayerView(player: player)
                Rectangle().fill(AppTheme.border).frame(height: 1)
            }

            WorkspaceHeader(viewModel: viewModel)
            TranscriptToolbar(viewModel: viewModel)

            if let transcript = viewModel.transcript {
                TranscriptView(viewModel: viewModel, selectionManager: viewModel.selectionManager, transcript: transcript)
            } else if !viewModel.isLoading {
                WelcomeView(viewModel: viewModel)
            }
        }
    }
}

struct WorkspaceHeader: View {
    @ObservedObject var viewModel: TranscriptViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.transcript?.displayTitle ?? "转写工作台")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textTertiary)
            }

            Spacer()

            HStack(spacing: 8) {
                HeaderMetric(title: "历史", value: "\(viewModel.historyProjects.count)")
                HeaderMetric(title: "片段", value: "\(viewModel.transcript?.segments.count ?? 0)")
                HeaderMetric(title: "说话人", value: "\(viewModel.transcript?.speakerCount ?? 0)")
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .background(AppTheme.background)
    }

    private var subtitle: String {
        if viewModel.isLoading {
            return viewModel.loadingMessage
        }
        if let transcript = viewModel.transcript {
            return "来源：\(transcript.displaySource)"
        }
        return "导入本地文件开始转写，历史项目会自动保存到文档目录"
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

// MARK: - Embedded Settings

struct EmbeddedSettingsView: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("设置")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

            SettingsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 24)
        }
        .background(AppTheme.background)
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @ObservedObject var viewModel: TranscriptViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .center, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("转写工作台")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(AppTheme.textPrimary)
                        Text("导入本地文件，或粘贴在线视频链接开始转写。历史记录会自动归档。")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                        .frame(width: 72, height: 72)
                        .background(AppTheme.accentSubtle)
                        .cornerRadius(AppTheme.cornerRadiusMedium)
                }

                HStack(alignment: .top, spacing: 16) {
                    ActionPanel(icon: "folder", title: "本地文件", subtitle: "音频、视频、批量文件") {
                        VStack(spacing: 10) {
                            PrimaryActionButton(icon: "plus", title: "导入本地文件", action: openFilePicker)
                            SecondaryActionButton(icon: "square.stack.3d.up", title: "批量处理", action: openBatchPicker)
                        }
                    }

                    ActionPanel(icon: "link", title: "在线视频", subtitle: "YouTube、B 站、抖音等公开视频") {
                        VStack(spacing: 10) {
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
                            .background(AppTheme.background)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                                    .stroke(AppTheme.border)
                            )
                            .cornerRadius(AppTheme.cornerRadiusMedium)

                            PrimaryActionButton(icon: "arrow.down.circle", title: "解析并转写") {
                                viewModel.processOnlineVideo(urlString: viewModel.onlineVideoURL)
                            }
                            .disabled(viewModel.onlineVideoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .opacity(viewModel.onlineVideoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                        }
                    }
                }

                SetupChecklist(viewModel: viewModel)
            }
            .padding(28)
            .frame(maxWidth: 860)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
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
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                        .lineLimit(1)
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

struct SetupChecklist: View {
    @ObservedObject var viewModel: TranscriptViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("启动检查")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                if !viewModel.isWhisperModelAvailable {
                    Button(action: viewModel.openModelDirectory) {
                        Text("打开模型目录")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                ForEach(viewModel.setupStatusItems) { item in
                    SetupStatusTile(item: item)
                }
            }
        }
        .padding(16)
        .background(AppTheme.surface)
        .cornerRadius(AppTheme.cornerRadiusMedium)
    }
}

struct SetupStatusTile: View {
    let item: TranscriptViewModel.SetupStatusItem

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: item.isAvailable ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(item.isAvailable ? AppTheme.success : AppTheme.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppTheme.textPrimary)
                Text(item.detail)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(AppTheme.background)
        .cornerRadius(AppTheme.cornerRadiusSmall)
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
                Spacer()
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(AppTheme.textPrimary)
            .cornerRadius(AppTheme.cornerRadiusMedium)
        }
        .buttonStyle(.plain)
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
                Spacer()
            }
            .foregroundColor(AppTheme.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(AppTheme.background)
            .cornerRadius(AppTheme.cornerRadiusMedium)
        }
        .buttonStyle(.plain)
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
