import Foundation

struct OnlineVideoDownload {
    let originalURL: URL
    let title: String
    let audioURL: URL
}

final class OnlineVideoService {
    var isAvailable: Bool {
        ytDLPPath != nil
    }

    func downloadAudio(from urlString: String) throws -> OnlineVideoDownload {
        guard let originalURL = URL(string: urlString), originalURL.scheme != nil else {
            throw OnlineVideoError.invalidURL
        }
        guard let ytDLPPath else {
            throw OnlineVideoError.ytDLPNotInstalled
        }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dean-online-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let outputTemplate = tempDirectory.appendingPathComponent("%(title).200B-%(id)s.%(ext)s").path
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytDLPPath)
        process.arguments = [
            "--no-playlist",
            "--extract-audio",
            "--audio-format", "m4a",
            "--print", "after_move:%(title)s",
            "--output", outputTemplate,
            originalURL.absoluteString
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: tempDirectory)
            throw OnlineVideoError.downloadFailed(errorOutput.isEmpty ? output : errorOutput)
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        guard let audioURL = files.first(where: { ["m4a", "mp3", "wav", "aac", "opus"].contains($0.pathExtension.lowercased()) }) else {
            try? FileManager.default.removeItem(at: tempDirectory)
            throw OnlineVideoError.downloadedAudioMissing
        }

        let title = output
            .split(separator: "\n")
            .last
            .map { String($0) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return OnlineVideoDownload(
            originalURL: originalURL,
            title: title?.isEmpty == false ? title! : originalURL.absoluteString,
            audioURL: audioURL
        )
    }

    func cleanup(download: OnlineVideoDownload) {
        let directory = download.audioURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: directory)
    }

    private var ytDLPPath: String? {
        let candidates = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]

        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return match
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "yt-dlp"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == false ? output : nil
        } catch {
            return nil
        }
    }
}

enum OnlineVideoError: LocalizedError {
    case invalidURL
    case ytDLPNotInstalled
    case downloadFailed(String)
    case downloadedAudioMissing

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "视频链接无效"
        case .ytDLPNotInstalled:
            return "未安装 yt-dlp。请先运行：brew install yt-dlp"
        case .downloadFailed(let message):
            return "在线视频下载失败：\(message)"
        case .downloadedAudioMissing:
            return "在线视频下载完成，但没有找到可转写的音频文件"
        }
    }
}

