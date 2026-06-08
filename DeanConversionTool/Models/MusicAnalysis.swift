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

struct MusicAnalysis: Codable, Equatable {
    let sourceURL: URL
    let createdAt: Date
    let scanMode: MusicScanMode
    let tracks: [RecognizedTrack]
    let unmatchedSampleCount: Int
    let providerName: String?
    let warning: String?
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
