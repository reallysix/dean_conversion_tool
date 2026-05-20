import Foundation

/// Service for audio transcription using whisper-cli command line tool
/// This approach runs whisper as a subprocess to avoid library integration issues
class WhisperService {
    private let whisperCLIPath = "/opt/homebrew/bin/whisper-cli"

    /// Check if whisper-cli is available
    var isModelLoaded: Bool {
        return isCLIAvailable
    }

    var isCLIAvailable: Bool {
        return FileManager.default.isExecutableFile(atPath: whisperCLIPath)
    }

    var isModelAvailable: Bool {
        return FileManager.default.fileExists(atPath: modelPath)
    }

    var modelPath: String {
        return getModelPath()
    }

    /// Get the path to the whisper model
    private func getModelPath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelDir = appSupport.appendingPathComponent("DeanConversion/models")
        return modelDir.appendingPathComponent("ggml-large-v3.bin").path
    }

    /// Transcribe an audio file using whisper-cli
    /// - Parameters:
    ///   - audioPath: Path to the WAV audio file (16kHz, mono, 16-bit PCM)
    ///   - language: Optional language code (e.g., "zh", "en", "ja")
    ///   - onProgress: Optional progress callback (0.0 to 1.0)
    ///   - onComplete: Completion handler with result or error
    func transcribe(audioPath: String, language: String? = nil, onProgress: ((Double) -> Void)? = nil, onComplete: @escaping (Result<[TranscriptSegment], Error>) -> Void) {
        guard FileManager.default.fileExists(atPath: whisperCLIPath) else {
            onComplete(.failure(WhisperError.modelNotLoaded))
            return
        }

        let modelPath = getModelPath()
        guard FileManager.default.fileExists(atPath: modelPath) else {
            onComplete(.failure(WhisperError.modelNotFound(modelPath)))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Configure whisper-cli arguments
            var arguments = [
                "-m", modelPath,
                "-f", audioPath,
                "-oj",  // Output JSON for structured data
                "--no-prints",
                "-l", language ?? "auto"  // Auto-detect language by default
            ]

            let process = Process()
            process.executableURL = URL(fileURLWithPath: self.whisperCLIPath)
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                guard process.terminationStatus == 0 else {
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    DispatchQueue.main.async {
                        onComplete(.failure(WhisperError.transcriptionFailed))
                    }
                    return
                }

                // Parse the JSON output
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let segments = self.parseWhisperOutput(output)

                DispatchQueue.main.async {
                    onComplete(.success(segments))
                }

            } catch {
                DispatchQueue.main.async {
                    onComplete(.failure(WhisperError.processFailed(error)))
                }
            }
        }
    }

    /// Detected language from last transcription
    private(set) var detectedLanguage: String?

    /// Parse whisper-cli JSON output
    private func parseWhisperOutput(_ output: String) -> [TranscriptSegment] {
        // Find JSON data in output (whisper-cli outputs other info before JSON)
        guard let jsonData = output.data(using: .utf8) else {
            return []
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let result = json["result"] as? [[String: Any]] else {
                // Try to parse as plain text if JSON fails
                return parsePlainTextOutput(output)
            }

            // Extract detected language
            if let lang = json["language"] as? String {
                self.detectedLanguage = lang
            }

            var segments: [TranscriptSegment] = []
            for item in result {
                guard let timestamps = item["timestamps"] as? [String: Any],
                      let from = timestamps["from"] as? Double,
                      let to = timestamps["to"] as? Double,
                      let text = item["text"] as? String else {
                    continue
                }

                let segment = TranscriptSegment(
                    startTime: from,
                    endTime: to,
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                segments.append(segment)
            }

            return segments

        } catch {
            return parsePlainTextOutput(output)
        }
    }

    /// Parse plain text output as fallback
    private func parsePlainTextOutput(_ output: String) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // Match pattern: [00:00:00.000 --> 00:00:05.000]  Text here
            let pattern = "\\[(\\d{2}):(\\d{2}):(\\d{2}\\.\\d{3})\\s*-->\\s*(\\d{2}):(\\d{2}):(\\d{2}\\.\\d{3})\\]\\s*(.*)"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
                continue
            }

            guard let startRange = Range(match.range(at: 1), in: line),
                  let startMin = Range(match.range(at: 2), in: line),
                  let startSec = Range(match.range(at: 3), in: line),
                  let endRange = Range(match.range(at: 4), in: line),
                  let endMin = Range(match.range(at: 5), in: line),
                  let endSec = Range(match.range(at: 6), in: line),
                  let textRange = Range(match.range(at: 7), in: line) else {
                continue
            }

            let startHours = Double(line[startRange]) ?? 0
            let startMinutes = Double(line[startMin]) ?? 0
            let startSeconds = Double(line[startSec]) ?? 0
            let startTime = startHours * 3600 + startMinutes * 60 + startSeconds

            let endHours = Double(line[endRange]) ?? 0
            let endMinutes = Double(line[endMin]) ?? 0
            let endSeconds = Double(line[endSec]) ?? 0
            let endTime = endHours * 3600 + endMinutes * 60 + endSeconds

            let text = String(line[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty {
                let segment = TranscriptSegment(
                    startTime: startTime,
                    endTime: endTime,
                    text: text
                )
                segments.append(segment)
            }
        }

        return segments
    }

    /// Transcribe and return a Transcript object
    func transcribeWithMetadata(audioPath: String, language: String? = nil, onProgress: ((Double) -> Void)? = nil, onComplete: @escaping (Result<Transcript, Error>) -> Void) {
        transcribe(audioPath: audioPath, language: language, onProgress: onProgress) { result in
            switch result {
            case .success(let segments):
                // Get audio duration
                let audioService = AudioPreprocessingService()
                let duration = (try? audioService.getAudioDuration(path: audioPath)) ?? 0

                // Use detected language if not explicitly specified
                let transcriptLanguage = language ?? self.detectedLanguage

                let transcript = Transcript(
                    sourceURL: URL(fileURLWithPath: audioPath),
                    segments: segments,
                    language: transcriptLanguage,
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
    case processFailed(Error)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "模型文件未找到：\(path)"
        case .modelLoadFailed:
            return "Whisper 模型加载失败"
        case .modelNotLoaded:
            return "whisper-cli 未找到。请安装 whisper-cpp：brew install whisper-cpp"
        case .audioLoadFailed:
            return "音频文件加载失败"
        case .transcriptionFailed:
            return "转写失败"
        case .processFailed(let error):
            return "进程执行失败：\(error.localizedDescription)"
        }
    }
}
