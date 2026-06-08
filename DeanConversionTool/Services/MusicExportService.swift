import Foundation

enum MusicExportFormat: CaseIterable {
    case json
    case txt

    var fileExtension: String {
        switch self {
        case .json:
            return "json"
        case .txt:
            return "txt"
        }
    }

    var displayName: String {
        switch self {
        case .json:
            return "音乐分析 JSON"
        case .txt:
            return "音乐列表 TXT"
        }
    }
}

final class MusicExportService {
    func export(
        analysis: MusicAnalysis,
        format: MusicExportFormat,
        outputURL: URL
    ) throws {
        let data: Data
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            data = try encoder.encode(analysis)
        case .txt:
            data = Data(textContent(for: analysis).utf8)
        }

        try data.write(to: outputURL, options: .atomic)
    }

    private func textContent(for analysis: MusicAnalysis) -> String {
        analysis.tracks.map { track in
            let timeRange: String
            if let startTime = track.startTime, let endTime = track.endTime {
                timeRange = "\(formatTime(startTime))-\(formatTime(endTime))"
            } else {
                timeRange = "--:--"
            }

            var details = ["[\(timeRange)] \(track.title)"]
            if let artist = track.artist, !artist.isEmpty {
                details[0] += " - \(artist)"
            }
            if let album = track.album, !album.isEmpty {
                details.append("专辑 \(album)")
            }
            if let confidence = track.confidence {
                details.append("置信度 \(String(format: "%.0f", confidence))")
            }
            details.append(track.source.displayName)
            return details.joined(separator: " | ")
        }.joined(separator: "\n")
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
