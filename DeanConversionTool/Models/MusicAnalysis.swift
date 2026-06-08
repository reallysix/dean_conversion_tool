import Foundation

enum MusicRecognitionSource: String, Codable, Equatable {
    case platformMetadata
    case xfyunACRCloud
    case backend
    case shazamKit

    var displayName: String {
        switch self {
        case .platformMetadata:
            return "平台标注"
        case .xfyunACRCloud:
            return "讯飞 ACRCloud"
        case .backend:
            return "在线识别"
        case .shazamKit:
            return "ShazamKit"
        }
    }
}

enum MusicScanMode: String, Codable, CaseIterable, Equatable {
    case off
    case quick
    case deep

    var displayName: String {
        switch self {
        case .off:
            return "关闭"
        case .quick:
            return "快速识别"
        case .deep:
            return "深度识别"
        }
    }

    var maxSampleCount: Int {
        switch self {
        case .off:
            return 0
        case .quick:
            return 3
        case .deep:
            return 10
        }
    }
}

struct RecognizedTrack: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let artist: String?
    let album: String?
    let startTime: TimeInterval?
    let endTime: TimeInterval?
    let confidence: Double?
    let source: MusicRecognitionSource
    let providerRecordingID: String?
}

enum MusicAnalysisOutcome: String, Codable, Equatable {
    case notConfigured
    case completed
    case partialFailure
    case failed
}

struct MusicAnalysis: Codable, Equatable {
    let sourceURL: URL
    let createdAt: Date
    let scanMode: MusicScanMode
    let tracks: [RecognizedTrack]
    let unmatchedSampleCount: Int
    let providerName: String?
    let warning: String?
    let outcome: MusicAnalysisOutcome
    let submittedSampleCount: Int

    init(
        sourceURL: URL,
        createdAt: Date,
        scanMode: MusicScanMode,
        tracks: [RecognizedTrack],
        unmatchedSampleCount: Int,
        providerName: String?,
        warning: String?,
        outcome: MusicAnalysisOutcome = .completed,
        submittedSampleCount: Int = 0
    ) {
        self.sourceURL = sourceURL
        self.createdAt = createdAt
        self.scanMode = scanMode
        self.tracks = tracks
        self.unmatchedSampleCount = unmatchedSampleCount
        self.providerName = providerName
        self.warning = warning
        self.outcome = outcome
        self.submittedSampleCount = submittedSampleCount
    }

    private enum CodingKeys: String, CodingKey {
        case sourceURL
        case createdAt
        case scanMode
        case tracks
        case unmatchedSampleCount
        case providerName
        case warning
        case outcome
        case submittedSampleCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceURL = try container.decode(URL.self, forKey: .sourceURL)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        scanMode = try container.decode(MusicScanMode.self, forKey: .scanMode)
        tracks = try container.decode([RecognizedTrack].self, forKey: .tracks)
        unmatchedSampleCount = try container.decode(Int.self, forKey: .unmatchedSampleCount)
        providerName = try container.decodeIfPresent(String.self, forKey: .providerName)
        warning = try container.decodeIfPresent(String.self, forKey: .warning)
        outcome = try container.decodeIfPresent(
            MusicAnalysisOutcome.self,
            forKey: .outcome
        ) ?? .completed
        submittedSampleCount = try container.decodeIfPresent(
            Int.self,
            forKey: .submittedSampleCount
        ) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(scanMode, forKey: .scanMode)
        try container.encode(tracks, forKey: .tracks)
        try container.encode(unmatchedSampleCount, forKey: .unmatchedSampleCount)
        try container.encodeIfPresent(providerName, forKey: .providerName)
        try container.encodeIfPresent(warning, forKey: .warning)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(submittedSampleCount, forKey: .submittedSampleCount)
    }
}

struct MusicSampleWindow: Equatable {
    let startTime: TimeInterval
    let duration: TimeInterval
}

struct MusicAudioSample: Equatable {
    let id: UUID
    let audioURL: URL
    let startTime: TimeInterval
    let duration: TimeInterval
}

struct MusicMatch: Equatable {
    let providerRecordingID: String
    let title: String
    let artist: String?
    let album: String?
    let confidence: Double?
    let playOffset: TimeInterval?
}

protocol MusicRecognitionProvider {
    var name: String { get }

    func recognize(sample: MusicAudioSample) async throws -> [MusicMatch]
}
