import Foundation

/// Service for audio transcription using whisper.cpp
/// This service wraps the whisper.cpp library via Bridging Header
class WhisperService {
    private var context: OpaquePointer?
    private let sentimentService = SentimentAnalysisService()

    /// Check if a model is loaded
    var isModelLoaded: Bool {
        return context != nil
    }

    /// Deinitialize whisper context
    deinit {
        if let context = context {
            whisper_free(context)
        }
    }

    /// Load the whisper model from file
    /// - Parameter modelPath: Path to the GGML model file
    /// - Throws: WhisperError if loading fails
    func loadModel(modelPath: String) throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw WhisperError.modelNotFound(modelPath)
        }

        // Free existing context if any
        if let context = context {
            whisper_free(context)
        }

        var params = whisper_context_default_params()
        params.use_gpu = true  // Enable Metal GPU acceleration

        guard let newContext = whisper_init_from_file_with_params(modelPath, params) else {
            throw WhisperError.modelLoadFailed
        }

        self.context = newContext
    }

    /// Transcribe an audio file
    /// - Parameters:
    ///   - audioPath: Path to the WAV audio file (16kHz, mono, 16-bit PCM)
    ///   - language: Optional language code (e.g., "zh", "en", "ja")
    ///   - onProgress: Optional progress callback (0.0 to 1.0)
    ///   - onComplete: Completion handler with result or error
    func transcribe(audioPath: String, language: String? = nil, onProgress: ((Double) -> Void)? = nil, onComplete: @escaping (Result<[TranscriptSegment], Error>) -> Void) {
        guard let context = context else {
            onComplete(.failure(WhisperError.modelNotLoaded))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Configure whisper parameters
            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.print_special = false
            params.print_progress = false
            params.print_realtime = false
            params.print_timestamps = false
            params.translate = false
            params.single_segment = false
            params.no_timestamps = false
            params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))  // Leave 2 cores free

            // Set language if specified
            if let language = language {
                language.withCString { langPtr in
                    var langCopy = langPtr
                    // Note: This is a simplified approach. In production, you'd need to handle this properly
                }
            }

            // Load audio data
            guard let audioData = self.loadAudio(path: audioPath) else {
                DispatchQueue.main.async {
                    onComplete(.failure(WhisperError.audioLoadFailed))
                }
                return
            }

            // Run inference
            let result = audioData.withUnsafeBufferPointer { buffer in
                whisper_full(context, params, buffer.baseAddress, Int32(audioData.count), nil, nil, nil)
            }

            if result == 0 {
                // Extract segments
                let segments = self.extractSegments(context: context)
                DispatchQueue.main.async {
                    onComplete(.success(segments))
                }
            } else {
                DispatchQueue.main.async {
                    onComplete(.failure(WhisperError.transcriptionFailed))
                }
            }
        }
    }

    /// Load audio file and convert to Float32 array for whisper.cpp
    private func loadAudio(path: String) -> [Float]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }

        // WAV header is 44 bytes, skip it
        guard data.count > 44 else { return nil }

        let audioData = data[44...]
        let sampleCount = audioData.count / 2  // 16-bit = 2 bytes per sample

        var floatArray = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let byteIndex = i * 2
            let sample = Int16(audioData[byteIndex]) | (Int16(audioData[byteIndex + 1]) << 8)
            floatArray[i] = Float(sample) / 32768.0
        }

        return floatArray
    }

    /// Extract transcript segments from whisper context
    private func extractSegments(context: OpaquePointer) -> [TranscriptSegment] {
        var segments = [TranscriptSegment]()
        let nSegments = whisper_full_n_segments(context)

        for i in 0..<nSegments {
            guard let textPtr = whisper_full_get_segment_text(context, i) else { continue }

            let startTime = whisper_full_get_segment_t0(context, i)
            let endTime = whisper_full_get_segment_t1(context, i)

            let text = String(cString: textPtr)
            let startSeconds = Double(startTime) / 100.0  // whisper uses centiseconds
            let endSeconds = Double(endTime) / 100.0

            let segment = TranscriptSegment(
                startTime: startSeconds,
                endTime: endSeconds,
                text: text.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            segments.append(segment)
        }

        return segments
    }

    /// Transcribe with sentiment analysis
    func transcribeWithSentiment(audioPath: String, language: String? = nil, onProgress: ((Double) -> Void)? = nil, onComplete: @escaping (Result<Transcript, Error>) -> Void) {
        transcribe(audioPath: audioPath, language: language, onProgress: onProgress) { result in
            switch result {
            case .success(let segments):
                // Analyze sentiment for each segment
                let segmentsWithSentiment = self.sentimentService.analyzeSegments(segments)

                // Get audio duration
                let audioService = AudioPreprocessingService()
                let duration = (try? audioService.getAudioDuration(path: audioPath)) ?? 0

                let transcript = Transcript(
                    sourceURL: URL(fileURLWithPath: audioPath),
                    segments: segmentsWithSentiment,
                    language: language,
                    duration: duration
                )

                onComplete(.success(transcript))

            case .failure(let error):
                onComplete(.failure(error))
            }
        }
    }
}

/// Whisper-specific errors
enum WhisperError: LocalizedError {
    case modelNotFound(String)
    case modelLoadFailed
    case modelNotLoaded
    case audioLoadFailed
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Model file not found: \(path)"
        case .modelLoadFailed:
            return "Failed to load whisper model"
        case .modelNotLoaded:
            return "No model loaded. Call loadModel() first"
        case .audioLoadFailed:
            return "Failed to load audio file"
        case .transcriptionFailed:
            return "Transcription failed"
        }
    }
}
