import Foundation
import SwiftUI
import Combine

/// Main ViewModel coordinating the full transcription pipeline
@MainActor
class TranscriptViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var transcript: Transcript?
    @Published var isLoading = false
    @Published var loadingMessage = ""
    @Published var progress: Double = 0.0
    @Published var error: String?
    @Published var selectedSegments: Set<UUID> = []
    @Published var searchText = ""
    @Published var selectedFormat: ExportFormat = .markdown

    // MARK: - Services
    private let whisperService = WhisperService()
    private let audioService = AudioPreprocessingService()
    private let diarizationService = SpeakerDiarizationService()
    private let exportService = ExportService()
    private let sentimentService = SentimentAnalysisService()

    // MARK: - State
    private var tempWavPath: String?

    // MARK: - Computed Properties
    var filteredSegments: [TranscriptSegment] {
        guard let transcript = transcript else { return [] }

        if searchText.isEmpty {
            return transcript.segments
        } else {
            return transcript.segments.filter { segment in
                segment.text.localizedCaseInsensitiveContains(searchText) ||
                (segment.speaker?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }

    var speakers: [String] {
        return transcript?.speakers ?? []
    }

    var emotionSummary: SentimentSummary? {
        guard let transcript = transcript else { return nil }
        return sentimentService.getSummary(for: transcript)
    }

    var isModelLoaded: Bool {
        return whisperService.isModelLoaded
    }

    var isPythonAvailable: Bool {
        return diarizationService.isAvailable
    }

    var isFFmpegAvailable: Bool {
        return audioService.isFFmpegAvailable
    }

    // MARK: - Initialization
    init() {
        // Don't load model in init - load lazily when needed
    }

    /// Load the whisper model
    func loadModel() {
        let modelPath = getModelPath()
        do {
            try whisperService.loadModel(modelPath: modelPath)
            print("Model loaded successfully from: \(modelPath)")
        } catch {
            self.error = "Failed to load model: \(error.localizedDescription)"
        }
    }

    /// Load model lazily when needed
    private func ensureModelLoaded() throws {
        guard !whisperService.isModelLoaded else { return }
        let modelPath = getModelPath()
        try whisperService.loadModel(modelPath: modelPath)
    }

    /// Get the path to the whisper model
    private func getModelPath() -> String {
        // Check Application Support first
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelDir = appSupport.appendingPathComponent("DeanConversion/models")
        let modelPath = modelDir.appendingPathComponent("ggml-large-v3.bin").path

        if FileManager.default.fileExists(atPath: modelPath) {
            return modelPath
        }

        // Fallback to home directory
        let homeModelPath = NSHomeDirectory() + "/Library/Application Support/DeanConversion/models/ggml-large-v3.bin"
        if FileManager.default.fileExists(atPath: homeModelPath) {
            return homeModelPath
        }

        // Return default path (will fail if not exists)
        return modelPath
    }

    // MARK: - Main Pipeline

    /// Process an audio/video file through the full pipeline
    func processFile(url: URL) {
        guard !isLoading else { return }

        isLoading = true
        error = nil
        transcript = nil
        progress = 0.0

        Task {
            do {
                // Step 0: Ensure model is loaded
                try ensureModelLoaded()

                // Step 1: Preprocess audio
                updateLoading("Preparing audio file...", progress: 0.1)
                let wavPath = try preprocessAudio(inputPath: url.path)
                tempWavPath = wavPath

                // Step 2: Transcribe with whisper
                updateLoading("Transcribing audio...", progress: 0.3)
                let transcribedSegments = try await transcribeAudio(audioPath: wavPath)

                // Step 3: Speaker diarization
                updateLoading("Identifying speakers...", progress: 0.7)
                let diarizedSegments = try await diarizeSpeakers(audioPath: wavPath, segments: transcribedSegments)

                // Step 4: Create transcript
                updateLoading("Finalizing transcript...", progress: 0.9)
                let duration = try audioService.getAudioDuration(path: url.path)
                let finalTranscript = Transcript(
                    sourceURL: url,
                    segments: diarizedSegments,
                    duration: duration
                )

                // Update UI
                self.transcript = finalTranscript
                self.progress = 1.0
                self.loadingMessage = "Complete!"

                // Clean up
                cleanupTempFiles()

            } catch {
                self.error = error.localizedDescription
                cleanupTempFiles()
            }

            isLoading = false
        }
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
            whisperService.transcribeWithSentiment(
                audioPath: audioPath,
                language: nil  // Auto-detect language
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.progress = 0.3 + (progress * 0.4)  // Map to 0.3-0.7 range
                }
            } onComplete: { result in
                switch result {
                case .success(let transcript):
                    continuation.resume(returning: transcript.segments)
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
        panel.title = "Export Transcript"
        panel.nameFieldStringValue = "\(transcript.sourceURL.deletingPathExtension().lastPathComponent)_transcript.\(exportService.fileExtension(for: exportFormat))"
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
                    self?.error = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Utility Functions

    private func updateLoading(_ message: String, progress: Double) {
        self.loadingMessage = message
        self.progress = progress
    }

    private func cleanupTempFiles() {
        if let tempPath = tempWavPath {
            audioService.cleanupTempFile(tempPath)
            tempWavPath = nil
        }
    }

    /// Clear the current transcript
    func clearTranscript() {
        transcript = nil
        selectedSegments.removeAll()
        error = nil
        progress = 0.0
    }

    /// Copy selected segments to clipboard
    func copySelectedSegments() {
        guard let transcript = transcript else { return }

        let selected = transcript.segments.filter { selectedSegments.contains($0.id) }
        let text = selected.map { $0.text }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Select all segments
    func selectAllSegments() {
        guard let transcript = transcript else { return }
        selectedSegments = Set(transcript.segments.map { $0.id })
    }

    /// Deselect all segments
    func deselectAllSegments() {
        selectedSegments.removeAll()
    }
}
