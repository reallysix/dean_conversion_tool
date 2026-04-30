import SwiftUI

/// Main transcript display view
struct TranscriptView: View {
    @ObservedObject var viewModel: TranscriptViewModel
    let transcript: Transcript

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            TranscriptToolbar(viewModel: viewModel, transcript: transcript)

            Divider()

            // Main content area
            HSplitView {
                // Transcript segments list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.filteredSegments) { segment in
                            SegmentRow(
                                segment: segment,
                                isSelected: viewModel.selectedSegments.contains(segment.id),
                                onToggle: { toggleSelection(segment.id) }
                            )
                        }
                    }
                    .padding()
                }

                // Sentiment summary sidebar
                if let summary = viewModel.emotionSummary {
                    SentimentSummaryView(summary: summary, transcript: transcript)
                        .frame(width: 250)
                }
            }
        }
    }

    private func toggleSelection(_ id: UUID) {
        if viewModel.selectedSegments.contains(id) {
            viewModel.selectedSegments.remove(id)
        } else {
            viewModel.selectedSegments.insert(id)
        }
    }
}

/// Toolbar for transcript operations
struct TranscriptToolbar: View {
    @ObservedObject var viewModel: TranscriptViewModel
    let transcript: Transcript

    var body: some View {
        HStack(spacing: 16) {
            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(transcript.sourceURL.lastPathComponent)
                    .font(.headline)
                Text("\(transcript.segments.count) segments • \(transcript.speakerCount) speakers • \(formatDuration(transcript.duration))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search transcript...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 200)

                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)

            Divider()
                .frame(height: 20)

            // Export menu
            Menu {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Button(action: { viewModel.exportTranscript(format: format) }) {
                        Label(exportService.formatDisplayName(for: format),
                              systemImage: iconForFormat(format))
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private let exportService = ExportService()

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func iconForFormat(_ format: ExportFormat) -> String {
        switch format {
        case .srt: return "subtitles"
        case .txt: return "doc.text"
        case .markdown: return "doc.richtext"
        case .html: return "globe"
        case .json: return "doc.badge.gearshape"
        }
    }
}

/// Individual segment row
struct SegmentRow: View {
    let segment: TranscriptSegment
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Selection checkbox
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            // Timestamp
            Text(segment.displayTimestamp)
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 50, alignment: .leading)

            // Speaker badge
            if let speaker = segment.speaker {
                Text(speaker)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(speakerColor(speaker).opacity(0.2))
                    .foregroundColor(speakerColor(speaker))
                    .cornerRadius(4)
            }

            // Emotion indicator
            if let sentiment = segment.sentiment {
                Text(sentiment.emotion.emoji)
                    .font(.caption)
            }

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(segment.text)
                    .font(.body)
                    .textSelection(.enabled)

                // Sentiment details (expandable)
                if let sentiment = segment.sentiment {
                    SentimentDetailView(sentiment: sentiment)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .onHover { hovering in
            // Visual feedback on hover
        }
    }

    private func speakerColor(_ speaker: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .indigo]
        let hash = abs(speaker.hashValue)
        return colors[hash % colors.count]
    }
}

/// Sentiment detail view
struct SentimentDetailView: View {
    let sentiment: SentimentResult

    var body: some View {
        HStack(spacing: 8) {
            // Score bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)

                    Rectangle()
                        .fill(scoreColor)
                        .frame(width: geometry.size.width * CGFloat(abs(sentiment.score)), height: 4)
                }
            }
            .frame(width: 60, height: 4)

            // Score value
            Text(String(format: "%.2f", sentiment.score))
                .font(.caption2)
                .foregroundColor(.secondary)

            // Confidence
            Text("\(Int(sentiment.confidence * 100))%")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var scoreColor: Color {
        if sentiment.score > 0.3 {
            return .green
        } else if sentiment.score < -0.3 {
            return .red
        } else {
            return .gray
        }
    }
}

/// Sentiment summary view
struct SentimentSummaryView: View {
    let summary: SentimentSummary
    let transcript: Transcript

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                Text("Sentiment Analysis")
                    .font(.headline)

                // Overall score
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overall Sentiment")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack {
                        Text(String(format: "%.2f", summary.averageScore))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(scoreColor)

                        Spacer()

                        Text(summary.dominantEmotion.emoji)
                            .font(.title)
                    }

                    // Score bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 8)

                            Rectangle()
                                .fill(scoreGradient)
                                .frame(width: geometry.size.width * CGFloat((summary.averageScore + 1) / 2), height: 8)
                        }
                    }
                    .frame(height: 8)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Distribution
                VStack(alignment: .leading, spacing: 8) {
                    Text("Distribution")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    DistributionBar(
                        positive: summary.positivePercentage,
                        neutral: summary.neutralPercentage,
                        negative: summary.negativePercentage
                    )

                    HStack {
                        Label("Positive", systemImage: "hand.thumbsup.fill")
                            .foregroundColor(.green)
                        Spacer()
                        Text("\(Int(summary.positivePercentage))%")
                            .font(.caption)
                    }

                    HStack {
                        Label("Neutral", systemImage: "minus.circle.fill")
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(Int(summary.neutralPercentage))%")
                            .font(.caption)
                    }

                    HStack {
                        Label("Negative", systemImage: "hand.thumbsdown.fill")
                            .foregroundColor(.red)
                        Spacer()
                        Text("\(Int(summary.negativePercentage))%")
                            .font(.caption)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Emotion breakdown
                VStack(alignment: .leading, spacing: 8) {
                    Text("Emotions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ForEach(EmotionType.allCases, id: \.self) { emotion in
                        if let count = summary.emotionDistribution[emotion], count > 0 {
                            HStack {
                                Text(emotion.emoji)
                                Text(emotion.rawValue)
                                    .font(.caption)
                                Spacer()
                                Text("\(count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Speaker breakdown
                if transcript.speakerCount > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Speakers")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ForEach(transcript.speakers, id: \.self) { speaker in
                            let speakerSegments = transcript.segments.filter { $0.speaker == speaker }
                            let speakerCount = speakerSegments.count

                            HStack {
                                Circle()
                                    .fill(speakerColor(speaker))
                                    .frame(width: 8, height: 8)
                                Text(speaker)
                                    .font(.caption)
                                Spacer()
                                Text("\(speakerCount) segments")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
    }

    private var scoreColor: Color {
        if summary.averageScore > 0.3 {
            return .green
        } else if summary.averageScore < -0.3 {
            return .red
        } else {
            return .gray
        }
    }

    private var scoreGradient: LinearGradient {
        LinearGradient(
            colors: [.red, .gray, .green],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func speakerColor(_ speaker: String) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .indigo]
        let hash = abs(speaker.hashValue)
        return colors[hash % colors.count]
    }
}

/// Distribution bar showing positive/neutral/negative
struct DistributionBar: View {
    let positive: Double
    let neutral: Double
    let negative: Double

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if positive > 0 {
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geometry.size.width * CGFloat(positive / 100))
                }
                if neutral > 0 {
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: geometry.size.width * CGFloat(neutral / 100))
                }
                if negative > 0 {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: geometry.size.width * CGFloat(negative / 100))
                }
            }
        }
        .frame(height: 8)
        .cornerRadius(4)
    }
}

#Preview {
    TranscriptView(
        viewModel: TranscriptViewModel(),
        transcript: Transcript(
            sourceURL: URL(fileURLWithPath: "/test.mp3"),
            segments: [
                TranscriptSegment(
                    startTime: 0,
                    endTime: 5.0,
                    text: "Hello world",
                    speaker: "Speaker 1",
                    sentiment: SentimentResult(score: 0.5, emotion: .positive, confidence: 0.8)
                )
            ]
        )
    )
}
