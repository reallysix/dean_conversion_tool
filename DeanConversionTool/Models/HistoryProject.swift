import Foundation

enum ProjectSourceType: String, Codable {
    case localFile
    case onlineVideo

    var displayName: String {
        switch self {
        case .localFile:
            return "本地文件"
        case .onlineVideo:
            return "在线视频"
        }
    }
}

enum ProjectStatus: String, Codable {
    case completed
    case failed

    var displayName: String {
        switch self {
        case .completed:
            return "已完成"
        case .failed:
            return "失败"
        }
    }
}

struct ProjectOutputs: Codable, Equatable {
    var transcriptJSON: String?
    var subtitlesSRT: String?
    var transcriptTXT: String?
    var transcriptMarkdown: String?
}

struct OnlineSourceMetadata: Codable, Equatable {
    var title: String
    var originalURL: String
    var platform: String
    var createdAt: Date
}

struct HistoryProject: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var sourceType: ProjectSourceType
    var sourceLocation: String
    var onlineMetadata: OnlineSourceMetadata?
    var createdAt: Date
    var updatedAt: Date
    var duration: TimeInterval
    var segmentCount: Int
    var status: ProjectStatus
    var projectDirectory: String
    var outputs: ProjectOutputs

    var projectURL: URL {
        URL(fileURLWithPath: projectDirectory)
    }

    var transcriptURL: URL? {
        guard let transcriptJSON = outputs.transcriptJSON else { return nil }
        return projectURL.appendingPathComponent(transcriptJSON)
    }
}
