import Foundation
import SwiftUI
import Combine
import AVFoundation
import AVKit

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

    // Selection is managed separately to avoid re-renders
    let selectionManager = SelectionManager()

    // Video player
    @Published var player: AVPlayer?
    @Published var isVideoFile = false

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

    var isPythonAvailable: Bool {
        return diarizationService.isAvailable
    }

    var isFFmpegAvailable: Bool {
        return audioService.isFFmpegAvailable
    }

    var isYTDLPAvailable: Bool {
        return onlineVideoService.isAvailable
    }

    var setupStatusItems: [SetupStatusItem] {
        [
            SetupStatusItem(name: "Whisper CLI", isAvailable: isWhisperCLIAvailable, detail: "brew install whisper-cpp"),
            SetupStatusItem(name: "Whisper 模型", isAvailable: isWhisperModelAvailable, detail: whisperModelPath),
            SetupStatusItem(name: "FFmpeg", isAvailable: isFFmpegAvailable, detail: "brew install ffmpeg"),
            SetupStatusItem(name: "yt-dlp", isAvailable: isYTDLPAvailable, detail: "brew install yt-dlp"),
            SetupStatusItem(name: "Python 说话人识别", isAvailable: isPythonAvailable, detail: "可选：pyannote.audio")
        ]
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
        transcript = nil
        progress = 0.0

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
        guard validateRequiredSetup(includeOnlineVideo: true) else { return }

        isLoading = true
        error = nil
        transcript = nil
        player = nil
        isVideoFile = false
        progress = 0.0

        Task {
            var download: OnlineVideoDownload?
            do {
                updateLoading("正在下载在线视频音频...", progress: 0.05)
                let downloadedVideo = try onlineVideoService.downloadAudio(from: trimmedURL)
                download = downloadedVideo

                let finalTranscript = try await processFileInternal(
                    url: downloadedVideo.audioURL,
                    sourceURL: downloadedVideo.originalURL,
                    sourceTitle: downloadedVideo.title
                ) { message, progress in
                    self.updateLoading(message, progress: 0.1 + progress * 0.9)
                }

                self.transcript = finalTranscript
                self.archiveTranscript(finalTranscript, sourceType: .onlineVideo)
                self.progress = 1.0
                self.loadingMessage = "完成！"
            } catch {
                self.error = error.localizedDescription
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
        let panel = NSSavePanel()
        panel.title = "导出文稿"
        panel.nameFieldStringValue = "\(transcript.displayTitle)_transcript.\(exportService.fileExtension(for: exportFormat))"
        panel.allowedContentTypes = [.text, .json, .html]

        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }

            do {
                try self?.exportService.export(
                    transcript: transcript,
                    format: exportFormat,
                    outputPath: url.path
                )
            } catch {
                Task { @MainActor in
                    self?.error = "导出失败：\(error.localizedDescription)"
                }
            }
        }
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
            selectedProjectID = project.id
            error = nil
            searchText = ""
            selectionManager.deselectAll()
            cachedSegments = []
            cachedTranscriptID = nil
            cachedSearchText = nil

            let videoExtensions = ["mp4", "mov", "avi", "mkv", "webm", "m4v"]
            let sourceURL = archivedTranscript.sourceURL
            isVideoFile = sourceURL.isFileURL && videoExtensions.contains(sourceURL.pathExtension.lowercased())
            player = isVideoFile ? AVPlayer(url: sourceURL) : nil
        } catch {
            self.error = "打开历史项目失败：\(error.localizedDescription)"
        }
    }

    private func archiveTranscript(_ transcript: Transcript, sourceType: ProjectSourceType) {
        do {
            let project = try historyStore.saveTranscriptProject(transcript: transcript, sourceType: sourceType)
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
                self.objectWillChange.send()
            case .failure(let downloadError):
                if (downloadError as NSError).code == NSURLErrorCancelled {
                    self.modelDownloadMessage = "模型下载已取消"
                } else {
                    self.modelDownloadMessage = "模型下载失败"
                    self.error = "模型下载失败：\(downloadError.localizedDescription)"
                }
            }
        }
    }

    func cancelModelDownload() {
        guard isDownloadingModel else { return }
        modelDownloadService.cancel()
        isDownloadingModel = false
        modelDownloadMessage = "模型下载已取消"
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
        selectedProjectID = nil
        selectionManager.deselectAll()
        cachedSegments = []
        cachedTranscriptID = nil
        cachedSearchText = nil
        error = nil
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
        guard let player = player else { return }
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
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
