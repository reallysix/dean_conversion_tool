import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct TranscriptView: View {
    @ObservedObject var viewModel: TranscriptViewModel
    @ObservedObject var selectionManager: SelectionManager
    let transcript: Transcript

    var body: some View {
        SpeakerGroupedListView(
            segments: viewModel.filteredSegments,
            selectedIDs: selectionManager.selectedIDs,
            activeSegmentID: viewModel.activePlaybackSegmentID,
            onToggle: { id in selectionManager.toggle(id) },
            onSeek: { time in viewModel.seekTo(time: time) }
        )
    }
}

// MARK: - Toolbar

struct TranscriptToolbar: View {
    @ObservedObject var viewModel: TranscriptViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Import button
            Button(action: { openFilePicker() }) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("导入音频/视频文件")

            Spacer()

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
                TextField("搜索...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textPrimary)
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.surface)
            .cornerRadius(AppTheme.cornerRadiusSmall)
            .frame(width: 200)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.workspace)
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
}

// MARK: - Speaker Grouped List

struct SpeakerGroupedListView: View {
    let segments: [TranscriptSegment]
    let selectedIDs: Set<UUID>
    let activeSegmentID: UUID?
    let onToggle: (UUID) -> Void
    let onSeek: ((TimeInterval) -> Void)?

    private var groupedBlocks: [(speaker: String?, segments: [TranscriptSegment])] {
        var blocks: [(speaker: String?, segments: [TranscriptSegment])] = []
        var currentSpeaker: String? = nil
        var currentSegments: [TranscriptSegment] = []

        for segment in segments {
            if segment.speaker != currentSpeaker {
                if !currentSegments.isEmpty {
                    blocks.append((speaker: currentSpeaker, segments: currentSegments))
                }
                currentSpeaker = segment.speaker
                currentSegments = [segment]
            } else {
                currentSegments.append(segment)
            }
        }
        if !currentSegments.isEmpty {
            blocks.append((speaker: currentSpeaker, segments: currentSegments))
        }
        return blocks
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groupedBlocks.indices, id: \.self) { index in
                        let block = groupedBlocks[index]
                        SpeakerBlock(
                            speaker: block.speaker,
                            segments: block.segments,
                            selectedIDs: selectedIDs,
                            activeSegmentID: activeSegmentID,
                            onToggle: onToggle,
                            onSeek: onSeek
                        )
                    }
                }
                .padding(20)
            }
            .onChange(of: activeSegmentID) {
                guard let activeSegmentID else { return }
                withAnimation(.easeOut(duration: 0.24)) {
                    proxy.scrollTo(activeSegmentID, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Speaker Block

struct SpeakerBlock: View {
    let speaker: String?
    let segments: [TranscriptSegment]
    let selectedIDs: Set<UUID>
    let activeSegmentID: UUID?
    let onToggle: (UUID) -> Void
    let onSeek: ((TimeInterval) -> Void)?

    private var timeRange: String {
        guard let first = segments.first, let last = segments.last else { return "" }
        return "\(first.displayTimestamp) - \(last.displayTimestamp)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SpeakerAvatar(name: speaker ?? "?")
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(speaker ?? "未知")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(timeRange)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .padding(.bottom, 4)

                ForEach(segments) { segment in
                    TranscriptLine(
                        segment: segment,
                        isSelected: selectedIDs.contains(segment.id),
                        isActive: activeSegmentID == segment.id,
                        onToggle: { onToggle(segment.id) },
                        onSeek: onSeek
                    )
                    .id(segment.id)
                }
            }
        }
    }
}

// MARK: - Speaker Avatar

struct SpeakerAvatar: View {
    let name: String

    private var initials: String {
        if name.contains(" ") {
            let parts = name.split(separator: " ")
            if let last = parts.last, let num = Int(last) {
                return "\(num)"
            }
            return parts.compactMap { $0.first }.prefix(2).map(String.init).joined()
        }
        return String(name.prefix(2))
    }

    private var avatarColor: Color {
        let hash = abs(name.hashValue)
        return AppTheme.speakerColors[hash % AppTheme.speakerColors.count]
    }

    var body: some View {
        Text(initials)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 28, height: 28)
            .background(avatarColor)
            .clipShape(Circle())
    }
}

// MARK: - Transcript Line

struct TranscriptLine: View, Equatable {
    let segment: TranscriptSegment
    let isSelected: Bool
    let isActive: Bool
    let onToggle: () -> Void
    let onSeek: ((TimeInterval) -> Void)?

    static func == (lhs: TranscriptLine, rhs: TranscriptLine) -> Bool {
        lhs.segment.id == rhs.segment.id &&
        lhs.segment.text == rhs.segment.text &&
        lhs.segment.speaker == rhs.segment.speaker &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isActive == rhs.isActive
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? AppTheme.accent : AppTheme.textTertiary)
            }
            .buttonStyle(.plain)

            Text(segment.displayTimestamp)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isActive ? AppTheme.textPrimary : AppTheme.accent)
                .padding(.horizontal, isActive ? 6 : 0)
                .padding(.vertical, isActive ? 2 : 0)
                .background(isActive ? AppTheme.accentWarm.opacity(0.75) : Color.clear)
                .cornerRadius(AppTheme.cornerRadiusSmall)
                .onTapGesture { onSeek?(segment.startTime) }
                .help("点击跳转到此时间点")

            Text(segment.text)
                .font(.system(size: 14))
                .fontWeight(isActive ? .medium : .regular)
                .foregroundColor(isActive ? AppTheme.textPrimary : AppTheme.textPrimary)
                .textSelection(.enabled)
                .lineSpacing(3)
                .onTapGesture { onSeek?(segment.startTime) }
                .help("点击跳转到此时间点")

            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(lineBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .stroke(isActive ? AppTheme.accentWarm.opacity(0.8) : Color.clear, lineWidth: 1)
        )
        .cornerRadius(AppTheme.cornerRadiusSmall)
    }

    private var lineBackground: Color {
        if isActive {
            return AppTheme.accentWarm.opacity(0.16)
        }
        if isSelected {
            return AppTheme.accentSubtle
        }
        return Color.clear
    }
}

#Preview {
    let vm = TranscriptViewModel()
    TranscriptView(
        viewModel: vm,
        selectionManager: vm.selectionManager,
        transcript: Transcript(
            sourceURL: URL(fileURLWithPath: "/test.mp3"),
            segments: [
                TranscriptSegment(startTime: 0, endTime: 5.0, text: "你好世界", speaker: "说话人 1"),
                TranscriptSegment(startTime: 5.0, endTime: 10.0, text: "今天天气不错", speaker: "说话人 1"),
                TranscriptSegment(startTime: 10.0, endTime: 15.0, text: "是的，阳光很好", speaker: "说话人 2")
            ]
        )
    )
    .preferredColorScheme(.dark)
}
