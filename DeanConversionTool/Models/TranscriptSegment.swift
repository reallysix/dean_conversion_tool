import Foundation

/// Represents a single segment of transcribed text with metadata
struct TranscriptSegment: Identifiable, Codable {
    let id: UUID
    let startTime: TimeInterval
    let endTime: TimeInterval
    var text: String
    var speaker: String?
    var sentiment: SentimentResult?

    init(id: UUID = UUID(), startTime: TimeInterval, endTime: TimeInterval, text: String, speaker: String? = nil, sentiment: SentimentResult? = nil) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.speaker = speaker
        self.sentiment = sentiment
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

/// Sentiment analysis result for a segment
struct SentimentResult: Codable {
    let score: Double  // -1.0 (negative) to 1.0 (positive)
    let emotion: EmotionType
    let confidence: Double  // 0.0 to 1.0
}

/// Supported emotion types
enum EmotionType: String, Codable, CaseIterable {
    case positive = "积极"
    case negative = "消极"
    case neutral = "中性"
    case excited = "兴奋"
    case angry = "愤怒"
    case sad = "悲伤"
    case surprised = "惊讶"

    /// Color for UI display
    var color: String {
        switch self {
        case .positive: return "green"
        case .negative: return "red"
        case .neutral: return "gray"
        case .excited: return "orange"
        case .angry: return "red"
        case .sad: return "blue"
        case .surprised: return "purple"
        }
    }

    /// Emoji for display
    var emoji: String {
        switch self {
        case .positive: return "😊"
        case .negative: return "😞"
        case .neutral: return "😐"
        case .excited: return "🤩"
        case .angry: return "😠"
        case .sad: return "😢"
        case .surprised: return "😲"
        }
    }
}

/// Complete transcript with all segments and metadata
struct Transcript: Identifiable, Codable {
    let id: UUID
    let sourceURL: URL
    let createdAt: Date
    var segments: [TranscriptSegment]
    let language: String?
    let duration: TimeInterval

    init(id: UUID = UUID(), sourceURL: URL, createdAt: Date = Date(), segments: [TranscriptSegment], language: String? = nil, duration: TimeInterval = 0) {
        self.id = id
        self.sourceURL = sourceURL
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

    /// Average sentiment score
    var averageSentiment: Double {
        let sentiments = segments.compactMap { $0.sentiment?.score }
        guard !sentiments.isEmpty else { return 0.0 }
        return sentiments.reduce(0, +) / Double(sentiments.count)
    }

    /// Emotion distribution
    var emotionDistribution: [EmotionType: Int] {
        var distribution: [EmotionType: Int] = [:]
        for segment in segments {
            if let emotion = segment.sentiment?.emotion {
                distribution[emotion, default: 0] += 1
            }
        }
        return distribution
    }
}
