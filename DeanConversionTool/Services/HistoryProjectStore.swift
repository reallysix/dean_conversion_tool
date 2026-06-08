import Foundation

final class HistoryProjectStore {
    private let fileManager: FileManager
    private let customProjectsRootURL: URL?
    private let exportService = ExportService()

    init(
        fileManager: FileManager = .default,
        projectsRootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.customProjectsRootURL = projectsRootURL
    }

    var projectsRootURL: URL {
        if let customProjectsRootURL {
            return customProjectsRootURL
        }
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent("DeanConversionTool/Projects", isDirectory: true)
    }

    func ensureProjectsDirectory() throws {
        try fileManager.createDirectory(at: projectsRootURL, withIntermediateDirectories: true)
    }

    func loadProjects() throws -> [HistoryProject] {
        try ensureProjectsDirectory()

        let projectDirectories = try fileManager.contentsOfDirectory(
            at: projectsRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let projects = projectDirectories.compactMap { directory -> HistoryProject? in
            let metadataURL = directory.appendingPathComponent("project.json")
            guard fileManager.fileExists(atPath: metadataURL.path),
                  let data = try? Data(contentsOf: metadataURL) else { return nil }
            return try? decoder.decode(HistoryProject.self, from: data)
        }

        return projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    func saveTranscriptProject(
        transcript: Transcript,
        sourceType: ProjectSourceType = .localFile,
        musicAnalysis: MusicAnalysis? = nil
    ) throws -> HistoryProject {
        try ensureProjectsDirectory()

        let title = transcript.displayTitle
        let createdAt = transcript.createdAt
        let projectID = transcript.id
        let projectDirectory = projectsRootURL.appendingPathComponent(
            "\(safeFileName(title))-\(timestampString(from: createdAt))-\(projectID.uuidString.prefix(8))",
            isDirectory: true
        )
        try fileManager.createDirectory(at: projectDirectory, withIntermediateDirectories: true)

        let transcriptFileName = "transcript.json"
        let srtFileName = "subtitles.srt"
        let txtFileName = "transcript.txt"
        let markdownFileName = "transcript.md"
        let musicAnalysisFileName = musicAnalysis == nil ? nil : "music-analysis.json"

        try writeTranscriptJSON(transcript, to: projectDirectory.appendingPathComponent(transcriptFileName))
        try exportService.export(transcript: transcript, format: .srt, outputPath: projectDirectory.appendingPathComponent(srtFileName).path)
        try exportService.export(transcript: transcript, format: .txt, outputPath: projectDirectory.appendingPathComponent(txtFileName).path)
        try exportService.export(transcript: transcript, format: .markdown, outputPath: projectDirectory.appendingPathComponent(markdownFileName).path)
        if let musicAnalysis, let musicAnalysisFileName {
            try writeMusicAnalysis(
                musicAnalysis,
                to: projectDirectory.appendingPathComponent(musicAnalysisFileName)
            )
        }

        let project = HistoryProject(
            id: projectID,
            title: title,
            sourceType: sourceType,
            sourceLocation: transcript.sourceURL.isFileURL ? transcript.sourceURL.path : transcript.sourceURL.absoluteString,
            onlineMetadata: onlineMetadata(for: transcript, sourceType: sourceType),
            createdAt: createdAt,
            updatedAt: Date(),
            duration: transcript.duration,
            segmentCount: transcript.segments.count,
            status: .completed,
            projectDirectory: projectDirectory.path,
            outputs: ProjectOutputs(
                transcriptJSON: transcriptFileName,
                subtitlesSRT: srtFileName,
                transcriptTXT: txtFileName,
                transcriptMarkdown: markdownFileName,
                musicAnalysisJSON: musicAnalysisFileName
            )
        )

        try writeProjectMetadata(project)
        return project
    }

    private func onlineMetadata(for transcript: Transcript, sourceType: ProjectSourceType) -> OnlineSourceMetadata? {
        guard sourceType == .onlineVideo else { return nil }

        return OnlineSourceMetadata(
            title: transcript.displayTitle,
            originalURL: transcript.sourceURL.absoluteString,
            platform: platformName(for: transcript.sourceURL),
            createdAt: transcript.createdAt
        )
    }

    func loadTranscript(for project: HistoryProject) throws -> Transcript {
        guard let transcriptURL = project.transcriptURL else {
            throw HistoryProjectError.missingTranscript
        }

        let data = try Data(contentsOf: transcriptURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Transcript.self, from: data)
    }

    func loadMusicAnalysis(for project: HistoryProject) throws -> MusicAnalysis? {
        guard let musicAnalysisURL = project.musicAnalysisURL else {
            return nil
        }

        let data = try Data(contentsOf: musicAnalysisURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MusicAnalysis.self, from: data)
    }

    private func writeProjectMetadata(_ project: HistoryProject) throws {
        let metadataURL = project.projectURL.appendingPathComponent("project.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        try data.write(to: metadataURL, options: .atomic)
    }

    private func writeTranscriptJSON(_ transcript: Transcript, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(transcript)
        try data.write(to: url, options: .atomic)
    }

    private func writeMusicAnalysis(_ analysis: MusicAnalysis, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(analysis)
        try data.write(to: url, options: .atomic)
    }

    private func safeFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = value.components(separatedBy: invalidCharacters).joined(separator: " ")
        let collapsed = cleaned.split(separator: " ").joined(separator: " ")
        return collapsed.isEmpty ? "Untitled" : collapsed
    }

    private func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private func platformName(for url: URL) -> String {
        guard let host = url.host?.lowercased() else { return "公开网页视频" }
        if host.contains("youtube.com") || host.contains("youtu.be") {
            return "YouTube"
        }
        if host.contains("bilibili.com") || host.contains("b23.tv") {
            return "B 站"
        }
        if host.contains("douyin.com") {
            return "抖音"
        }
        if host.contains("xiaohongshu.com") || host.contains("xhslink.com") {
            return "小红书"
        }
        if host.contains("tiktok.com") {
            return "TikTok"
        }
        if host.contains("vimeo.com") {
            return "Vimeo"
        }
        return "公开网页视频"
    }
}

enum HistoryProjectError: LocalizedError {
    case missingTranscript

    var errorDescription: String? {
        switch self {
        case .missingTranscript:
            return "历史项目缺少转写文件"
        }
    }
}
