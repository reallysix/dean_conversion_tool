import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WorkspaceSidebar: View {
    @ObservedObject var viewModel: TranscriptViewModel
    @Binding var selectedPanel: SidePanel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader

            VStack(spacing: 8) {
                SidebarActionButton(icon: "doc.text", title: "转写工作台", isSelected: selectedPanel == .transcript) {
                    selectedPanel = .transcript
                }
                SidebarActionButton(icon: "gearshape", title: "设置", isSelected: selectedPanel == .settings) {
                    selectedPanel = .settings
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)

            importActions

            Divider()
                .background(AppTheme.border)
                .padding(.vertical, 18)

            historySection

            if let project = viewModel.selectedHistoryProject {
                SelectedHistoryProjectCard(
                    project: project,
                    revealAction: viewModel.revealSelectedHistoryProject
                )
                .padding(.horizontal, 14)
                .padding(.top, 12)
            }

            Spacer(minLength: 12)
        }
        .frame(width: AppTheme.historySidebarWidth)
        .background(AppTheme.sidebarBackground)
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                Circle()
                    .fill(AppTheme.accentWarm)
                    .frame(width: 27, height: 27)
                Rectangle()
                    .fill(AppTheme.sidebarBackground)
                    .frame(width: 31, height: 14)
                    .offset(y: 2)
            }

            Text("Deanly")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
        }
        .padding(.horizontal, 22)
        .padding(.top, 58)
        .padding(.bottom, 22)
    }

    private var importActions: some View {
        VStack(spacing: 8) {
            SidebarActionButton(icon: "plus", title: "导入本地文件", isSelected: false, action: openFilePicker)
            SidebarActionButton(icon: "square.stack.3d.up", title: "批量处理", isSelected: false, action: openBatchPicker)
            SidebarActionButton(icon: "link", title: "粘贴在线视频", isSelected: false, action: openOnlineVideoPrompt)
        }
        .padding(.horizontal, 18)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("历史记录")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textTertiary)
                Spacer()
                Button(action: viewModel.loadHistoryProjects) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("刷新历史记录")
            }
            .padding(.horizontal, 22)

            if viewModel.historyProjects.isEmpty {
                Text("完成第一条转写后会自动归档")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.historyProjects) { project in
                            HistoryProjectRow(
                                project: project,
                                isSelected: viewModel.selectedProjectID == project.id
                            ) {
                                selectedPanel = .transcript
                                viewModel.openProject(project)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
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
            selectedPanel = .transcript
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
            selectedPanel = .transcript
            viewModel.batchQueue = panel.urls
            viewModel.showBatchSetup = true
        }
    }

    private func openOnlineVideoPrompt() {
        let alert = NSAlert()
        alert.messageText = "粘贴在线视频链接"
        alert.informativeText = "第一版支持 yt-dlp 可解析的公开视频链接。"
        alert.addButton(withTitle: "开始转写")
        alert.addButton(withTitle: "取消")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        textField.placeholderString = "https://..."
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let urlString = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedPanel = .transcript
        viewModel.processOnlineVideo(urlString: urlString)
    }
}

private struct SidebarActionButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer()
            }
            .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(isSelected ? AppTheme.textPrimary : Color.clear)
            .cornerRadius(AppTheme.cornerRadiusMedium)
        }
        .buttonStyle(WorkbenchPlainButtonStyle())
    }
}

private struct HistoryProjectRow: View {
    let project: HistoryProject
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                ProjectSourceIcon(project: project)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(project.title)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 0)

                        if project.status == .failed {
                            Text("失败")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(AppTheme.danger)
                        }
                    }

                    Text("\(project.sourceType.displayName) · \(formatDate(project.updatedAt))")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.textTertiary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        HistoryMetaLabel(icon: "clock", text: formatHistoryDuration(project.duration))
                        HistoryMetaLabel(icon: "text.alignleft", text: "\(project.segmentCount)")
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(isSelected ? AppTheme.surface : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                    .stroke(isSelected ? AppTheme.border : Color.clear, lineWidth: 1)
            )
            .cornerRadius(AppTheme.cornerRadiusMedium)
        }
        .buttonStyle(.plain)
        .help(project.sourceLocation)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

}

private struct ProjectSourceIcon: View {
    let project: HistoryProject

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .fill(project.sourceType == .onlineVideo ? AppTheme.accentWarm.opacity(0.25) : AppTheme.accentSubtle)
            Image(systemName: project.sourceType == .onlineVideo ? "link" : "doc.text")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(project.sourceType == .onlineVideo ? Color(hex: 0x8A6500) : AppTheme.accent)
        }
        .frame(width: 34, height: 34)
    }
}

private struct HistoryMetaLabel: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .medium))
            Text(text)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(AppTheme.textTertiary)
        .lineLimit(1)
    }
}

private struct SelectedHistoryProjectCard: View {
    let project: HistoryProject
    let revealAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProjectSourceIcon(project: project)
                    .scaleEffect(0.9)

                VStack(alignment: .leading, spacing: 2) {
                    Text("当前项目")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(AppTheme.textTertiary)
                    Text(project.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    HistoryMetaLabel(icon: "play.circle", text: project.sourceType.displayName)
                    HistoryMetaLabel(icon: "clock", text: formatHistoryDuration(project.duration))
                    HistoryMetaLabel(icon: "text.alignleft", text: "\(project.segmentCount)")
                }

                VStack(alignment: .leading, spacing: 4) {
                    HistoryMetaLabel(icon: "play.circle", text: project.sourceType.displayName)
                    HistoryMetaLabel(icon: "clock", text: formatHistoryDuration(project.duration))
                    HistoryMetaLabel(icon: "text.alignleft", text: "\(project.segmentCount)")
                }
            }

            Button(action: revealAction) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .semibold))
                    Text("打开归档目录")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundColor(AppTheme.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(AppTheme.surface)
                .cornerRadius(AppTheme.cornerRadiusSmall)
            }
            .buttonStyle(WorkbenchPlainButtonStyle())
            .help(project.projectDirectory)
        }
        .padding(12)
        .background(AppTheme.surfaceHover)
        .cornerRadius(AppTheme.cornerRadiusMedium)
    }
}

private func formatHistoryDuration(_ duration: TimeInterval) -> String {
    guard duration > 0 else { return "--:--" }
    let hours = Int(duration) / 3600
    let minutes = (Int(duration) % 3600) / 60
    let seconds = Int(duration) % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}
