import Foundation
import NaturalLanguage

/// Service for analyzing text sentiment and emotion using Apple's NaturalLanguage framework
class SentimentAnalysisService {
    private let tagger = NLTagger(tagSchemes: [.sentimentScore])

    /// Analyze sentiment of a text segment
    /// - Parameter text: The text to analyze
    /// - Returns: SentimentResult with score, emotion, and confidence
    func analyze(text: String) -> SentimentResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SentimentResult(score: 0.0, emotion: .neutral, confidence: 0.0)
        }

        tagger.string = text

        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)

        let score = Double(tag?.rawValue ?? "0") ?? 0.0
        let emotion = classifyEmotion(score: score, text: text)
        let confidence = calculateConfidence(score: score, text: text)

        return SentimentResult(score: score, emotion: emotion, confidence: confidence)
    }

    /// Classify emotion based on sentiment score and text content
    private func classifyEmotion(score: Double, text: String) -> EmotionType {
        // Check for exclamation marks indicating excitement
        let exclamationCount = text.filter { $0 == "!" || $0 == "！" }.count
        if exclamationCount >= 2 && score > 0.3 {
            return .excited
        }

        // Check for question marks indicating surprise
        let questionCount = text.filter { $0 == "?" || $0 == "？" }.count
        if questionCount >= 2 && score < -0.2 {
            return .surprised
        }

        // Classify based on score
        switch score {
        case 0.5...1.0:
            return .positive
        case 0.1..<0.5:
            return .positive
        case -0.1..<0.1:
            return .neutral
        case -0.5 ..< -0.1:
            return .negative
        case -1.0 ..< -0.5:
            // Check for anger keywords
            let angerKeywords = ["愤怒", "生气", "讨厌", "恨", "气死", "混蛋", "可恶"]
            if angerKeywords.contains(where: { text.contains($0) }) {
                return .angry
            }
            return .sad
        default:
            return .neutral
        }
    }

    /// Calculate confidence score based on score magnitude and text length
    private func calculateConfidence(score: Double, text: String) -> Double {
        // Higher confidence for stronger sentiments and longer texts
        let scoreConfidence = min(abs(score) * 1.5, 1.0)
        let lengthBonus = min(Double(text.count) / 100.0, 0.3)
        return min(scoreConfidence + lengthBonus, 1.0)
    }

    /// Batch analyze multiple texts
    func analyzeBatch(texts: [String]) -> [SentimentResult] {
        return texts.map { analyze(text: $0) }
    }

    /// Analyze transcript segments and update their sentiment
    func analyzeSegments(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        return segments.map { segment in
            var updatedSegment = segment
            updatedSegment.sentiment = analyze(text: segment.text)
            return updatedSegment
        }
    }

    /// Get overall sentiment summary for a transcript
    func getSummary(for transcript: Transcript) -> SentimentSummary {
        let sentiments = transcript.segments.compactMap { $0.sentiment }

        guard !sentiments.isEmpty else {
            return SentimentSummary(
                averageScore: 0.0,
                positiveCount: 0,
                negativeCount: 0,
                neutralCount: 0,
                dominantEmotion: .neutral,
                emotionDistribution: [:]
            )
        }

        let scores = sentiments.map { $0.score }
        let averageScore = scores.reduce(0, +) / Double(scores.count)

        var positiveCount = 0
        var negativeCount = 0
        var neutralCount = 0
        var emotionCounts: [EmotionType: Int] = [:]

        for sentiment in sentiments {
            switch sentiment.emotion {
            case .positive, .excited:
                positiveCount += 1
            case .negative, .angry, .sad:
                negativeCount += 1
            case .neutral, .surprised:
                neutralCount += 1
            }

            emotionCounts[sentiment.emotion, default: 0] += 1
        }

        let dominantEmotion = emotionCounts.max(by: { $0.value < $1.value })?.key ?? .neutral

        return SentimentSummary(
            averageScore: averageScore,
            positiveCount: positiveCount,
            negativeCount: negativeCount,
            neutralCount: neutralCount,
            dominantEmotion: dominantEmotion,
            emotionDistribution: emotionCounts
        )
    }
}

/// Summary of sentiment analysis results
struct SentimentSummary {
    let averageScore: Double
    let positiveCount: Int
    let negativeCount: Int
    let neutralCount: Int
    let dominantEmotion: EmotionType
    let emotionDistribution: [EmotionType: Int]

    var totalSegments: Int {
        return positiveCount + negativeCount + neutralCount
    }

    var positivePercentage: Double {
        guard totalSegments > 0 else { return 0.0 }
        return Double(positiveCount) / Double(totalSegments) * 100.0
    }

    var negativePercentage: Double {
        guard totalSegments > 0 else { return 0.0 }
        return Double(negativeCount) / Double(totalSegments) * 100.0
    }

    var neutralPercentage: Double {
        guard totalSegments > 0 else { return 0.0 }
        return Double(neutralCount) / Double(totalSegments) * 100.0
    }
}
