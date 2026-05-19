import Foundation

/// Represents a single segment of transcribed text with metadata
struct TranscriptSegment: Identifiable, Codable {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    var text: String
    var speaker: String?

    init(id: UUID = UUID(), startTime: TimeInterval, endTime: TimeInterval, text: String, speaker: String? = nil) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.speaker = speaker
    }

    /// Duration of this segment
    var duration: TimeInterval {
        return endTime - startTime
    }

    /// Formatted timestamp for SRT format
    var srtTimestamp: String {
        let start = formatTime(startTime)
        let end = formatTime(endTime)
        return "\(start) --> \(end)"
    }

    /// Formatted timestamp for display
    var displayTimestamp: String {
        return formatTimeDisplay(startTime)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }

    private func formatTimeDisplay(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// Complete transcript with all segments and metadata
struct Transcript: Identifiable, Codable {
    let id: UUID
    let sourceURL: URL
    let sourceTitle: String?
    let createdAt: Date
    var segments: [TranscriptSegment]
    let language: String?
    let duration: TimeInterval

    init(id: UUID = UUID(), sourceURL: URL, sourceTitle: String? = nil, createdAt: Date = Date(), segments: [TranscriptSegment], language: String? = nil, duration: TimeInterval = 0) {
        self.id = id
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.createdAt = createdAt
        self.segments = segments
        self.language = language
        self.duration = duration
    }

    /// Full text of the transcript
    var fullText: String {
        return segments.map { $0.text }.joined(separator: "\n")
    }

    /// Number of unique speakers
    var speakerCount: Int {
        let speakers = Set(segments.compactMap { $0.speaker })
        return speakers.count
    }

    /// List of all speakers
    var speakers: [String] {
        let speakers = Set(segments.compactMap { $0.speaker })
        return Array(speakers).sorted()
    }

    var displayTitle: String {
        if let sourceTitle, !sourceTitle.isEmpty {
            return sourceTitle
        }
        if sourceURL.isFileURL {
            return sourceURL.deletingPathExtension().lastPathComponent
        }
        return sourceURL.host ?? sourceURL.absoluteString
    }

    var displaySource: String {
        sourceURL.isFileURL ? sourceURL.path : sourceURL.absoluteString
    }
}
