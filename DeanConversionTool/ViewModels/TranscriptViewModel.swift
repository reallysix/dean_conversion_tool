import Foundation
import SwiftUI
import Combine
import AVFoundation
import AVKit
import AppKit

/// Separate selection manager to avoid triggering ViewModel re-renders
@MainActor
class SelectionManager: ObservableObject {
    @Published var selectedIDs: Set<UUID> = []

    func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func selectAll(_ ids: [UUID]) {
        selectedIDs = Set(ids)
    }

    func deselectAll() {
        selectedIDs.removeAll()
    }

    func isSelected(_ id: UUID) -> Bool {
        selectedIDs.contains(id)
    }
}

enum DependencyInstallError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let output):
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedOutput.isEmpty ? "安装命令执行失败。" : trimmedOutput
        }
    }
}

/// Main ViewModel coordinating the full transcription pipeline
@MainActor
class TranscriptViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var transcript: Transcript?
    @Published var isLoading = false
    @Published var loadingMessage = ""
    @Published var progress: Double = 0.0
    @Published var error: String?
    @Published var searchText = ""
    @Published var selectedFormat: ExportFormat = .markdown
    @Published var historyProjects: [HistoryProject] = []
    @Published var selectedProjectID: UUID?
    @Published var onlineVideoURL = ""
    @Published var isDownloadingModel = false
    @Published var modelDownloadProgress = 0.0
    @Published var modelDownloadMessage = ""
    @Published var modelDownloadIsError = false
    @Published var exportStatusMessage: String?
    @Published var exportStatusIsError = false
    @Published var lastExportedFileURL: URL?
    @Published var setupClipboardMessage: String?
    @Published var dependencyInstallMessage: String?
    @Published var dependencyInstallIsError = false
    @Published var isInstallingDependencies = false
    @Published var lastFailedOnlineVideoURLString: String?
    @Published var playbackSeekTime: TimeInterval?
    @Published var playbackSeekRequestID = UUID()
    @Published var playbackCurrentTime: TimeInterval = 0
    @Published var isResolvingOnlinePreview = false
    @Published var onlinePreviewError: String?
    @Published var musicScanMode: MusicScanMode = .off
    @Published var musicAnalysis: MusicAnalysis?
    @Published var musicAnalysisMessage: String?
    @Published var musicAnalysisIsError = false
    @Published var lastExportedMusicFileURL: URL?

    // Selection is managed separately to avoid re-renders
    let selectionManager = SelectionManager()

    // Video player
    @Published var player: AVPlayer?
    @Published var isVideoFile = false

    var selectedHistoryProject: HistoryProject? {
        guard let selectedProjectID else { return nil }
        return historyProjects.first { $0.id == selectedProjectID }
    }

    // Batch processing
    @Published var isBatchMode = false
    @Published var batchQueue: [URL] = []
    @Published var batchIndex: Int = 0
    @Published var batchTotal: Int = 0
    @Published var batchResults: [BatchResult] = []
    @Published var batchExportDirectory: URL?
    @Published var batchExportFormat: ExportFormat = .txt
    @Published var showBatchSetup = false
    @Published var showBatchSummary = false

    struct BatchResult {
        let url: URL
        let success: Bool
        let error: String?
    }

    struct SetupStatusItem: Identifiable {
        let id = UUID()
        let name: String
        let isAvailable: Bool
        let detail: String
        let installCommand: String?
        let isRequired: Bool
    }

    struct OnlineVideoInputState {
        let normalizedURLString: String?
        let platformName: String?
        let message: String
        let isReady: Bool
    }

    // Cached filtered segments
    private var cachedSegments: [TranscriptSegment] = []
    private var cachedSearchText: String?
    private var cachedTranscriptID: UUID?

    // MARK: - Services
    private let whisperService = WhisperService()
    private let audioService = AudioPreprocessingService()
    private let diarizationService = SpeakerDiarizationService()
    private let exportService = ExportService()
    private let historyStore = HistoryProjectStore()
    private let onlineVideoService = OnlineVideoService()
    private let modelDownloadService = ModelDownloadService()
    private let credentialStore: XFYunCredentialStoring = KeychainXFYunCredentialStore()
    private let musicSampleService = MusicSampleService()
    private let musicExportService = MusicExportService()

    // MARK: - State
    private var tempWavPath: String?

    // MARK: - Computed Properties
    var filteredSegments: [TranscriptSegment] {
        guard let transcript = transcript else { return [] }

        // Return cached if nothing changed
        if cachedTranscriptID == transcript.id && cachedSearchText == searchText {
            return cachedSegments
        }

        // Recalculate
        if searchText.isEmpty {
            cachedSegments = transcript.segments
        } else {
            cachedSegments = transcript.segments.filter { segment in
                segment.text.localizedCaseInsensitiveContains(searchText) ||
                (segment.speaker?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        cachedTranscriptID = transcript.id
        cachedSearchText = searchText
        return cachedSegments
    }

    var speakers: [String] {
        return transcript?.speakers ?? []
    }

    var activePlaybackSegmentID: UUID? {
        guard let transcript, playbackCurrentTime >= 0 else { return nil }
        return transcript.segments.first { segment in
            playbackCurrentTime >= segment.startTime && playbackCurrentTime < segment.endTime
        }?.id
    }

    var isModelLoaded: Bool {
        return whisperService.isModelLoaded
    }

    var isWhisperCLIAvailable: Bool {
        return whisperService.isCLIAvailable
    }

    var isWhisperModelAvailable: Bool {
        return whisperService.isModelAvailable
    }

    var whisperModelPath: String {
        return whisperService.modelPath
    }

    var whisperModelName: String {
        return ModelDownloadService.modelName
    }

    var whisperModelSizeDescription: String {
        return ModelDownloadService.modelSizeDescription
    }

    var whisperModelDirectory: String {
        return URL(fileURLWithPath: whisperModelPath).deletingLastPathComponent().path
    }

    var isPythonAvailable: Bool {
        return diarizationService.isAvailable
    }

    var isFFmpegAvailable: Bool {
        return audioService.isFFmpegAvailable
    }

    var isYTDLPAvailable: Bool {
        return onlineVideoService.isAvailable
    }

    var isDenoAvailable: Bool {
        return onlineVideoService.isDenoAvailable
    }

    var setupStatusItems: [SetupStatusItem] {
        [
            SetupStatusItem(
                name: "Whisper CLI",
                isAvailable: isWhisperCLIAvailable,
                detail: "本地转写核心工具",
                installCommand: "brew install whisper-cpp",
                isRequired: true
            ),
            SetupStatusItem(
                name: "Whisper 模型",
                isAvailable: isWhisperModelAvailable,
                detail: "保存位置：\(whisperModelPath)",
                installCommand: nil,
                isRequired: true
            ),
            SetupStatusItem(
                name: "FFmpeg / ffprobe",
                isAvailable: isFFmpegAvailable,
                detail: "音视频转码与时长读取",
                installCommand: "brew install ffmpeg",
                isRequired: true
            ),
            SetupStatusItem(
                name: "yt-dlp",
                isAvailable: isYTDLPAvailable,
                detail: "在线公开视频解析",
                installCommand: "brew install yt-dlp",
                isRequired: true
            ),
            SetupStatusItem(
                name: "Deno",
                isAvailable: isDenoAvailable,
                detail: "YouTube 解析建议安装",
                installCommand: "brew install deno",
                isRequired: false
            ),
            SetupStatusItem(
                name: "Python 说话人识别",
                isAvailable: isPythonAvailable,
                detail: "可选：pyannote.audio",
                installCommand: nil,
                isRequired: false
            )
        ]
    }

    var requiredSetupMissingCount: Int {
        setupStatusItems.filter { $0.isRequired && !$0.isAvailable }.count
    }

    var optionalSetupMissingCount: Int {
        setupStatusItems.filter { !$0.isRequired && !$0.isAvailable }.count
    }

    var canRetryOnlineVideo: Bool {
        lastFailedOnlineVideoURLString?.isEmpty == false && !isLoading
    }

    private var onlineVideoCookieSource: OnlineVideoCookieSource {
        let rawValue = UserDefaults.standard.string(forKey: "onlineVideoCookieSource")
        return OnlineVideoCookieSource(rawValue: rawValue ?? "") ?? .none
    }

    var onlineVideoInputState: OnlineVideoInputState {
        let trimmed = onlineVideoURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return OnlineVideoInputState(
                normalizedURLString: nil,
                platformName: nil,
                message: "粘贴公开视频链接后会自动识别平台",
                isReady: false
            )
        }

        guard let normalized = normalizedOnlineVideoURLString(from: trimmed),
              let url = URL(string: normalized),
              let host = url.host?.lowercased() else {
            return OnlineVideoInputState(
                normalizedURLString: nil,
                platformName: nil,
                message: "链接格式不对，请粘贴完整的视频地址",
                isReady: false
            )
        }

        let platformName = onlineVideoPlatformName(host: host)
        return OnlineVideoInputState(
            normalizedURLString: normalized,
            platformName: platformName,
            message: "已识别：\(platformName ?? "公开网页视频")",
            isReady: true
        )
    }

    // MARK: - Initialization
    init() {
        // Model loading happens in WhisperService via whisper-cli subprocess
        loadHistoryProjects()
    }

    // MARK: - Main Pipeline

    /// Process an audio/video file through the full pipeline (single-file mode)
    func processFile(url: URL) {
        guard !isLoading else { return }
        guard validateRequiredSetup(includeOnlineVideo: false) else { return }

        isLoading = true
        error = nil
        lastFailedOnlineVideoURLString = nil
        transcript = nil
        resetMusicAnalysis()
        progress = 0.0
        playbackCurrentTime = 0

        // Check if it's a video file and set up player
        let videoExtensions = ["mp4", "mov", "avi", "mkv", "webm", "m4v"]
        let fileExtension = url.pathExtension.lowercased()
        isVideoFile = videoExtensions.contains(fileExtension)

        if isVideoFile {
            let avPlayer = AVPlayer(url: url)
            avPlayer.preventsDisplaySleepDuringVideoPlayback = true
            player = avPlayer
        } else {
            player = nil
        }
        onlinePreviewError = nil
        isResolvingOnlinePreview = false

        Task {
            do {
                let finalTranscript = try await processFileInternal(url: url, sourceURL: url) { message, progress in
                    self.updateLoading(message, progress: progress)
                }

                self.transcript = finalTranscript
                self.archiveTranscript(finalTranscript, sourceType: .localFile)
                self.progress = 1.0
                self.loadingMessage = "完成！"
                cleanupTempFiles()

            } catch {
                self.error = error.localizedDescription
                cleanupTempFiles()
            }

            isLoading = false
        }
    }

    func processOnlineVideo(urlString: String) {
        guard !isLoading else { return }
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            error = "请先粘贴在线视频链接"
            return
        }
        guard let normalizedURLString = normalizedOnlineVideoURLString(from: trimmedURL) else {
            error = "视频链接无效，请检查后再试"
            return
        }
        guard validateRequiredSetup(includeOnlineVideo: true) else { return }

        let requestedMusicScanMode = musicScanMode
        isLoading = true
        error = nil
        lastFailedOnlineVideoURLString = nil
        transcript = nil
        resetMusicAnalysis()
        player = nil
        isVideoFile = false
        playbackCurrentTime = 0
        onlinePreviewError = nil
        isResolvingOnlinePreview = false
        progress = 0.0

        Task {
            var download: OnlineVideoDownload?
            do {
                updateLoading("正在下载在线视频音频...", progress: 0.05)
                let downloadedVideo = try onlineVideoService.downloadAudio(
                    from: normalizedURLString,
                    cookieSource: onlineVideoCookieSource
                )
                download = downloadedVideo

                let finalTranscript = try await processFileInternal(
                    url: downloadedVideo.audioURL,
                    sourceURL: downloadedVideo.originalURL,
                    sourceTitle: downloadedVideo.title
                ) { message, progress in
                    let scale = requestedMusicScanMode == .off ? 0.9 : 0.68
                    self.updateLoading(message, progress: 0.1 + progress * scale)
                }

                self.transcript = finalTranscript
                let analysis = await self.analyzeMusicIfRequested(
                    download: downloadedVideo,
                    transcript: finalTranscript,
                    mode: requestedMusicScanMode
                )
                self.musicAnalysis = analysis
                self.loadOnlinePreview(for: downloadedVideo.originalURL)
                self.archiveTranscript(
                    finalTranscript,
                    sourceType: .onlineVideo,
                    musicAnalysis: analysis
                )
                self.progress = 1.0
                self.loadingMessage = "完成！"
            } catch {
                self.error = error.localizedDescription
                self.lastFailedOnlineVideoURLString = normalizedURLString
            }

            if let download {
                onlineVideoService.cleanup(download: download)
            }
            cleanupTempFiles()
            isLoading = false
        }
    }

    /// Core pipeline: preprocess → transcribe → diarize → return Transcript
    private func processFileInternal(url: URL, sourceURL: URL, sourceTitle: String? = nil, onProgress: ((String, Double) -> Void)? = nil) async throws -> Transcript {
        // Step 1: Preprocess audio
        onProgress?("正在准备音频文件...", 0.1)
        let wavPath = try preprocessAudio(inputPath: url.path)
        defer { audioService.cleanupTempFile(wavPath) }

        // Step 2: Transcribe with whisper
        onProgress?("正在转写音频...", 0.3)
        let transcribedSegments = try await transcribeAudio(audioPath: wavPath)

        // Step 3: Speaker diarization
        onProgress?("正在识别说话人...", 0.7)
        let diarizedSegments = try await diarizeSpeakers(audioPath: wavPath, segments: transcribedSegments)

        // Step 4: Create transcript
        onProgress?("正在生成文稿...", 0.9)
        let duration = try audioService.getAudioDuration(path: url.path)

        return Transcript(
            sourceURL: sourceURL,
            sourceTitle: sourceTitle,
            segments: diarizedSegments,
            duration: duration
        )
    }

    // MARK: - Pipeline Steps

    /// Preprocess audio to whisper-compatible format
    private func preprocessAudio(inputPath: String) throws -> String {
        let outputDir = FileManager.default.temporaryDirectory
        let outputURL = outputDir.appendingPathComponent("whisper_input_\(UUID().uuidString).wav")

        try audioService.convertToWhisperFormat(
            inputPath: inputPath,
            outputPath: outputURL.path
        )

        return outputURL.path
    }

    /// Transcribe audio using whisper
    private func transcribeAudio(audioPath: String) async throws -> [TranscriptSegment] {
        return try await withCheckedThrowingContinuation { continuation in
            whisperService.transcribe(
                audioPath: audioPath,
                language: nil  // Auto-detect language
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.progress = 0.3 + (progress * 0.4)  // Map to 0.3-0.7 range
                }
            } onComplete: { result in
                switch result {
                case .success(let segments):
                    continuation.resume(returning: segments)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Perform speaker diarization
    private func diarizeSpeakers(audioPath: String, segments: [TranscriptSegment]) async throws -> [TranscriptSegment] {
        guard diarizationService.isAvailable else {
            // If diarization not available, return segments without speaker info
            return segments
        }

        return try await withCheckedThrowingContinuation { continuation in
            do {
                let diarizationSegments = try diarizationService.diarize(audioPath: audioPath) { [weak self] message in
                    Task { @MainActor in
                        self?.loadingMessage = message
                    }
                }

                let mergedSegments = diarizationService.mergeWithTranscript(
                    transcriptSegments: segments,
                    diarizationSegments: diarizationSegments
                )

                continuation.resume(returning: mergedSegments)
            } catch {
                // If diarization fails, return original segments
                print("Diarization failed: \(error), returning segments without speaker info")
                continuation.resume(returning: segments)
            }
        }
    }

    // MARK: - Export Functions

    /// Export transcript to file
    func exportTranscript(format: ExportFormat? = nil) {
        guard let transcript = transcript else { return }

        let exportFormat = format ?? selectedFormat
        exportStatusMessage = nil
        exportStatusIsError = false
        lastExportedFileURL = nil

        let panel = NSOpenPanel()
        panel.title = "选择导出目录"
        panel.prompt = "导出"
        panel.message = "将在所选目录中生成 \(exportService.formatDisplayName(for: exportFormat))"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let directoryURL = panel.url else { return }
        let url = uniqueExportURL(in: directoryURL, transcript: transcript, format: exportFormat)

        let didAccess = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try exportService.export(
                transcript: transcript,
                format: exportFormat,
                outputPath: url.path
            )
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ExportError.fileNotCreated(url.path)
            }

            error = nil
            exportStatusMessage = "已导出：\(url.lastPathComponent)"
            exportStatusIsError = false
            lastExportedFileURL = url
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let message = "导出失败：\(error.localizedDescription)"
            self.error = message
            exportStatusMessage = message
            exportStatusIsError = true
            lastExportedFileURL = nil
        }
    }

    func revealLastExportedFile() {
        guard let lastExportedFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastExportedFileURL])
    }

    func exportMusicAnalysis(format: MusicExportFormat) {
        guard let transcript, let musicAnalysis else { return }

        musicAnalysisMessage = nil
        musicAnalysisIsError = false
        lastExportedMusicFileURL = nil

        let panel = NSOpenPanel()
        panel.title = "选择导出目录"
        panel.prompt = "导出"
        panel.message = "将在所选目录中生成 \(format.displayName)"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let directoryURL = panel.url else { return }
        let outputURL = uniqueMusicExportURL(
            in: directoryURL,
            transcript: transcript,
            format: format
        )

        let didAccess = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try musicExportService.export(
                analysis: musicAnalysis,
                format: format,
                outputURL: outputURL
            )
            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                throw ExportError.fileNotCreated(outputURL.path)
            }

            musicAnalysisMessage = "已导出：\(outputURL.lastPathComponent)"
            musicAnalysisIsError = false
            lastExportedMusicFileURL = outputURL
            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
        } catch {
            musicAnalysisMessage = "音乐分析导出失败：\(error.localizedDescription)"
            musicAnalysisIsError = true
            lastExportedMusicFileURL = nil
        }
    }

    func revealLastExportedMusicFile() {
        guard let lastExportedMusicFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastExportedMusicFileURL])
    }

    private func uniqueExportURL(in directoryURL: URL, transcript: Transcript, format: ExportFormat) -> URL {
        let fileExtension = exportService.fileExtension(for: format)
        let baseName = sanitizedFileName("\(transcript.displayTitle)_transcript")
        var candidate = directoryURL.appendingPathComponent(baseName).appendingPathExtension(fileExtension)
        var index = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directoryURL
                .appendingPathComponent("\(baseName) \(index)")
                .appendingPathExtension(fileExtension)
            index += 1
        }

        return candidate
    }

    private func uniqueMusicExportURL(
        in directoryURL: URL,
        transcript: Transcript,
        format: MusicExportFormat
    ) -> URL {
        let baseName = sanitizedFileName("\(transcript.displayTitle)_music-analysis")
        var candidate = directoryURL
            .appendingPathComponent(baseName)
            .appendingPathExtension(format.fileExtension)
        var index = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directoryURL
                .appendingPathComponent("\(baseName) \(index)")
                .appendingPathExtension(format.fileExtension)
            index += 1
        }

        return candidate
    }

    private func sanitizedFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)

        let sanitized = name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return sanitized.isEmpty ? "transcript" : sanitized
    }

    // MARK: - History

    func loadHistoryProjects() {
        do {
            try historyStore.ensureProjectsDirectory()
            historyProjects = try historyStore.loadProjects()
        } catch {
            self.error = "历史目录初始化失败：\(error.localizedDescription)"
        }
    }

    func openProject(_ project: HistoryProject) {
        do {
            let archivedTranscript = try historyStore.loadTranscript(for: project)
            transcript = archivedTranscript
            musicAnalysis = try historyStore.loadMusicAnalysis(for: project)
            musicAnalysisMessage = musicAnalysis?.warning
            musicAnalysisIsError = musicAnalysis?.warning != nil
            lastExportedMusicFileURL = nil
            selectedProjectID = project.id
            error = nil
            searchText = ""
            playbackCurrentTime = 0
            selectionManager.deselectAll()
            cachedSegments = []
            cachedTranscriptID = nil
            cachedSearchText = nil

            let videoExtensions = ["mp4", "mov", "avi", "mkv", "webm", "m4v"]
            let sourceURL = archivedTranscript.sourceURL
            isVideoFile = sourceURL.isFileURL && videoExtensions.contains(sourceURL.pathExtension.lowercased())
            player = isVideoFile ? AVPlayer(url: sourceURL) : nil
            onlinePreviewError = nil
            isResolvingOnlinePreview = false
            if !sourceURL.isFileURL {
                loadOnlinePreview(for: sourceURL)
            }
            lastFailedOnlineVideoURLString = nil
        } catch {
            self.error = "打开历史项目失败：\(error.localizedDescription)"
        }
    }

    func revealSelectedHistoryProject() {
        guard let project = selectedHistoryProject else { return }
        NSWorkspace.shared.activateFileViewerSelecting([project.projectURL])
    }

    func loadOnlinePreview(for sourceURL: URL) {
        guard !sourceURL.isFileURL else { return }
        guard !isResolvingOnlinePreview else { return }

        isResolvingOnlinePreview = true
        onlinePreviewError = nil

        Task {
            do {
                let playableURL = try await resolvePlayableVideoURL(from: sourceURL.absoluteString)
                let previewPlayer = AVPlayer(url: playableURL)
                previewPlayer.preventsDisplaySleepDuringVideoPlayback = true
                player = previewPlayer
                isVideoFile = false
                onlinePreviewError = nil
            } catch {
                player = nil
                onlinePreviewError = "内嵌播放器暂不可用：\(error.localizedDescription)"
            }

            isResolvingOnlinePreview = false
        }
    }

    private func resolvePlayableVideoURL(from urlString: String) async throws -> URL {
        let cookieSource = onlineVideoCookieSource
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let playableURL = try OnlineVideoService().playableVideoURL(
                        from: urlString,
                        cookieSource: cookieSource
                    )
                    continuation.resume(returning: playableURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func retryOnlineVideo() {
        guard let lastFailedOnlineVideoURLString else { return }
        processOnlineVideo(urlString: lastFailedOnlineVideoURLString)
    }

    private func archiveTranscript(
        _ transcript: Transcript,
        sourceType: ProjectSourceType,
        musicAnalysis: MusicAnalysis? = nil
    ) {
        do {
            let project = try historyStore.saveTranscriptProject(
                transcript: transcript,
                sourceType: sourceType,
                musicAnalysis: musicAnalysis
            )
            selectedProjectID = project.id
            historyProjects = try historyStore.loadProjects()
        } catch {
            self.error = "历史归档失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Utility Functions

    private func updateLoading(_ message: String, progress: Double) {
        self.loadingMessage = message
        self.progress = progress
    }

    private func analyzeMusicIfRequested(
        download: OnlineVideoDownload,
        transcript: Transcript,
        mode: MusicScanMode
    ) async -> MusicAnalysis? {
        guard mode != .off else {
            return nil
        }

        updateLoading("正在准备背景音乐识别...", progress: 0.78)

        let provider: MusicRecognitionProvider?
        var credentialWarning: String?
        do {
            if let credentials = try credentialStore.load(), credentials.isComplete {
                provider = XFYunMusicRecognitionProvider(credentials: credentials)
            } else {
                provider = nil
            }
        } catch {
            provider = nil
            credentialWarning = error.localizedDescription
        }

        let service = MusicAnalysisService(
            sampleProducer: musicSampleService,
            provider: provider
        )
        let analysis = await service.analyze(
            sourceURL: download.originalURL,
            audioURL: download.audioURL,
            duration: transcript.duration,
            transcriptSegments: transcript.segments,
            metadata: download.metadata,
            mode: mode
        ) { completed, total in
            Task { @MainActor in
                let fraction = total > 0 ? Double(completed) / Double(total) : 1
                self.updateLoading(
                    "正在识别背景音乐 \(completed)/\(total)...",
                    progress: 0.78 + fraction * 0.18
                )
            }
        }

        let warning = credentialWarning ?? analysis.warning
        if let warning {
            musicAnalysisMessage = "文稿已完成，但背景音乐识别失败：\(warning)"
            musicAnalysisIsError = true
        } else {
            musicAnalysisMessage = analysis.tracks.isEmpty
                ? "背景音乐扫描完成，暂未识别到歌曲"
                : "已识别 \(analysis.tracks.count) 首背景音乐"
            musicAnalysisIsError = false
        }
        return analysis
    }

    private func resetMusicAnalysis() {
        musicAnalysis = nil
        musicAnalysisMessage = nil
        musicAnalysisIsError = false
        lastExportedMusicFileURL = nil
    }

    private func validateRequiredSetup(includeOnlineVideo: Bool) -> Bool {
        var missing: [String] = []

        if !isWhisperCLIAvailable {
            missing.append("Whisper CLI")
        }
        if !isWhisperModelAvailable {
            missing.append("Whisper 模型")
        }
        if !isFFmpegAvailable {
            missing.append("FFmpeg")
        }
        if includeOnlineVideo && !isYTDLPAvailable {
            missing.append("yt-dlp")
        }

        guard missing.isEmpty else {
            error = "开始前还缺少：\(missing.joined(separator: "、"))。请先按右侧状态或 README 完成安装。"
            return false
        }

        return true
    }

    private func normalizedOnlineVideoURLString(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: String
        if trimmed.contains("://") {
            candidate = trimmed
        } else if trimmed.hasPrefix("www.") || trimmed.contains(".") {
            candidate = "https://\(trimmed)"
        } else {
            candidate = trimmed
        }

        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            return nil
        }

        return candidate
    }

    private func onlineVideoPlatformName(host: String) -> String? {
        if host.contains("youtube.com") || host.contains("youtu.be") {
            return "YouTube"
        }
        if host.contains("bilibili.com") || host.contains("b23.tv") {
            return "B 站"
        }
        if host.contains("douyin.com") {
            return "抖音"
        }
        if host.contains("tiktok.com") {
            return "TikTok"
        }
        if host.contains("vimeo.com") {
            return "Vimeo"
        }
        return nil
    }

    func copyInstallCommand(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        setupClipboardMessage = "已复制：\(command)"
        error = nil
    }

    func copyDependencyCheckCommand() {
        copyInstallCommand("Scripts/check_dependencies.sh --install")
    }

    func installMissingDependencies() {
        guard !isInstallingDependencies else { return }

        let alert = NSAlert()
        alert.messageText = "安装缺失依赖？"
        alert.informativeText = "将调用 Homebrew 安装当前缺失的命令行工具。安装过程可能需要几分钟，期间请不要关闭应用。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "安装")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let scriptURL = dependencyInstallScriptURL() else {
            dependencyInstallMessage = "没有找到依赖安装脚本。"
            dependencyInstallIsError = true
            return
        }

        isInstallingDependencies = true
        dependencyInstallMessage = "正在安装缺失依赖..."
        dependencyInstallIsError = false
        setupClipboardMessage = nil
        error = nil

        Task {
            do {
                let output = try await runDependencyInstaller(scriptURL: scriptURL)
                dependencyInstallMessage = summarizeDependencyInstallOutput(output)
                dependencyInstallIsError = false
                objectWillChange.send()
            } catch {
                dependencyInstallMessage = "依赖安装失败：\(error.localizedDescription)"
                dependencyInstallIsError = true
            }

            isInstallingDependencies = false
        }
    }

    private func dependencyInstallScriptURL() -> URL? {
        if let bundledScriptURL = Bundle.main.url(forResource: "check_dependencies", withExtension: "sh") {
            return bundledScriptURL
        }

        let localScriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Scripts/check_dependencies.sh")
        if FileManager.default.fileExists(atPath: localScriptURL.path) {
            return localScriptURL
        }

        return nil
    }

    private func runDependencyInstaller(scriptURL: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [scriptURL.path, "--install"]

                var environment = ProcessInfo.processInfo.environment
                let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                if let path = environment["PATH"], !path.isEmpty {
                    environment["PATH"] = "\(fallbackPath):\(path)"
                } else {
                    environment["PATH"] = fallbackPath
                }
                process.environment = environment

                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = outputPipe

                do {
                    try process.run()
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    guard process.terminationStatus == 0 else {
                        throw DependencyInstallError.commandFailed(output)
                    }

                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func summarizeDependencyInstallOutput(_ output: String) -> String {
        if output.localizedCaseInsensitiveContains("All required command-line tools are installed") {
            return "核心依赖已经就绪。"
        }
        return "依赖安装完成，环境状态已刷新。"
    }

    func openModelDirectory() {
        let modelURL = URL(fileURLWithPath: whisperModelPath).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(modelURL)
    }

    func openModelDownloadPage() {
        NSWorkspace.shared.open(modelDownloadService.downloadPageURL)
    }

    func downloadWhisperModel() {
        guard !isDownloadingModel else { return }

        let destinationURL = URL(fileURLWithPath: whisperModelPath)
        isDownloadingModel = true
        modelDownloadProgress = 0
        modelDownloadMessage = "正在连接模型下载源..."
        modelDownloadIsError = false
        error = nil

        modelDownloadService.downloadModel(to: destinationURL) { [weak self] progress in
            guard let self else { return }
            self.modelDownloadProgress = progress
            self.modelDownloadMessage = "正在下载模型 \(Int(progress * 100))%"
        } onComplete: { [weak self] result in
            guard let self else { return }
            self.isDownloadingModel = false

            switch result {
            case .success:
                self.modelDownloadProgress = 1
                self.modelDownloadMessage = "模型已就绪"
                self.modelDownloadIsError = false
                self.objectWillChange.send()
            case .failure(let downloadError):
                if (downloadError as NSError).code == NSURLErrorCancelled {
                    self.modelDownloadMessage = "模型下载已取消"
                    self.modelDownloadIsError = false
                } else {
                    self.modelDownloadMessage = "模型下载失败：\(downloadError.localizedDescription)"
                    self.modelDownloadIsError = true
                    self.error = nil
                }
            }
        }
    }

    func cancelModelDownload() {
        guard isDownloadingModel else { return }
        modelDownloadService.cancel()
        isDownloadingModel = false
        modelDownloadMessage = "模型下载已取消"
        modelDownloadIsError = false
    }

    private func cleanupTempFiles() {
        if let tempPath = tempWavPath {
            audioService.cleanupTempFile(tempPath)
            tempWavPath = nil
        }
    }

    /// Clear the current transcript
    func clearTranscript() {
        player?.pause()
        player = nil
        isVideoFile = false
        transcript = nil
        resetMusicAnalysis()
        selectedProjectID = nil
        selectionManager.deselectAll()
        cachedSegments = []
        cachedTranscriptID = nil
        cachedSearchText = nil
        error = nil
        lastFailedOnlineVideoURLString = nil
        onlinePreviewError = nil
        isResolvingOnlinePreview = false
        progress = 0.0
    }

    /// Copy selected segments to clipboard
    func copySelectedSegments() {
        guard let transcript = transcript else { return }

        let selected = transcript.segments.filter { selectionManager.isSelected($0.id) }
        let text = selected.map { $0.text }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Select all segments
    func selectAllSegments() {
        guard let transcript = transcript else { return }
        selectionManager.selectAll(transcript.segments.map { $0.id })
    }

    /// Deselect all segments
    func deselectAllSegments() {
        selectionManager.deselectAll()
    }

    /// Seek video to a specific time
    func seekTo(time: TimeInterval) {
        playbackCurrentTime = max(0, time)
        playbackSeekTime = time
        playbackSeekRequestID = UUID()

        if let player {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    // MARK: - Batch Processing

    /// Start batch processing queued files
    func startBatch() {
        guard !isBatchMode, !batchQueue.isEmpty, batchExportDirectory != nil else { return }

        isBatchMode = true
        isLoading = true
        batchResults = []
        batchTotal = batchQueue.count
        batchIndex = 0
        error = nil
        transcript = nil
        player = nil
        isVideoFile = false

        Task {
            for (index, url) in batchQueue.enumerated() {
                guard isBatchMode else { break }  // cancelled

                batchIndex = index + 1
                updateLoading("批量处理 \(index + 1)/\(batchQueue.count): \(url.lastPathComponent)", progress: 0)

                do {
                    let finalTranscript = try await processFileInternal(url: url, sourceURL: url) { [weak self] message, progress in
                        guard let self = self else { return }
                        let overallProgress = Double(index) / Double(self.batchQueue.count) + progress / Double(self.batchQueue.count)
                        self.updateLoading("批量 \(index + 1)/\(self.batchQueue.count): \(message)", progress: overallProgress)
                    }

                    // Auto-export
                    let filename = url.deletingPathExtension().lastPathComponent + "_transcript"
                    let ext = exportService.fileExtension(for: batchExportFormat)
                    let outputPath = batchExportDirectory!.appendingPathComponent("\(filename).\(ext)").path
                    try exportService.export(transcript: finalTranscript, format: batchExportFormat, outputPath: outputPath)
                    archiveTranscript(finalTranscript, sourceType: .localFile)

                    batchResults.append(BatchResult(url: url, success: true, error: nil))

                } catch {
                    batchResults.append(BatchResult(url: url, success: false, error: error.localizedDescription))
                }
            }

            let succeeded = batchResults.filter { $0.success }.count
            let failed = batchResults.filter { !$0.success }.count
            loadingMessage = "批量完成：\(succeeded) 成功，\(failed) 失败"
            progress = 1.0

            isBatchMode = false
            isLoading = false
            showBatchSummary = true
        }
    }

    /// Cancel batch processing
    func cancelBatch() {
        isBatchMode = false
        isLoading = false
        loadingMessage = "已取消"
        progress = 0.0
    }
}
