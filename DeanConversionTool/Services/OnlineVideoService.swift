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
        process.environment = processEnvironment

        var arguments = [
            "--no-playlist",
            "--extract-audio",
            "--audio-format", "m4a",
            "--print", "after_move:%(title)s",
            "--output", outputTemplate,
        ]

        if let ffmpegLocation {
            arguments.append(contentsOf: ["--ffmpeg-location", ffmpegLocation])
        }

        if let denoPath {
            arguments.append(contentsOf: ["--js-runtimes", "deno:\(denoPath)"])
        }

        arguments.append(originalURL.absoluteString)
        process.arguments = arguments

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
        return executablePath(named: "yt-dlp", candidates: [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ])
    }

    private var ffmpegLocation: String? {
        if let ffmpegPath = executablePath(named: "ffmpeg", candidates: [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]) {
            return URL(fileURLWithPath: ffmpegPath).deletingLastPathComponent().path
        }

        return nil
    }

    private var denoPath: String? {
        executablePath(named: "deno", candidates: [
            "/opt/homebrew/bin/deno",
            "/usr/local/bin/deno",
            "/usr/bin/deno"
        ])
    }

    private var processEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let path = environment["PATH"], !path.isEmpty {
            environment["PATH"] = "\(fallbackPath):\(path)"
        } else {
            environment["PATH"] = fallbackPath
        }
        return environment
    }

    private func executablePath(named name: String, candidates: [String]) -> String? {
        let candidates = [
            candidates,
            ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"]
        ].flatMap { $0 }

        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return match
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        process.environment = processEnvironment
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
            return "在线视频下载失败：\(Self.userFacingDownloadMessage(from: message))"
        case .downloadedAudioMissing:
            return "在线视频下载完成，但没有找到可转写的音频文件"
        }
    }

    private static func userFacingDownloadMessage(from message: String) -> String {
        let lowercased = message.lowercased()

        if lowercased.contains("ffprobe and ffmpeg not found") || lowercased.contains("ffmpeg not found") {
            return "缺少 FFmpeg。请先安装 ffmpeg，或重新启动应用后再试。"
        }
        if lowercased.contains("unsupported url") {
            return "暂不支持这个链接，请确认它是公开视频链接。"
        }
        if lowercased.contains("private video") || lowercased.contains("sign in") || lowercased.contains("login") {
            return "这个视频需要登录或权限，当前版本仅支持公开视频。"
        }
        if lowercased.contains("video unavailable") || lowercased.contains("not available") {
            return "视频不可用，请确认链接可以在浏览器中正常打开。"
        }
        if lowercased.contains("network") || lowercased.contains("timed out") || lowercased.contains("connection") {
            return "网络连接失败，请稍后重试。"
        }

        let lines = message
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("WARNING:") }

        return lines.prefix(2).joined(separator: "\n")
    }
}
