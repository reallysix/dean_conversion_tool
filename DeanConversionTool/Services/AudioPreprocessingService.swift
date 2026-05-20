import Foundation

/// Service for preprocessing audio/video files to whisper-compatible format
class AudioPreprocessingService {
    private var ffmpegPath: String? {
        executablePath(named: "ffmpeg")
    }

    private var ffprobePath: String? {
        executablePath(named: "ffprobe")
    }

    /// Check if ffmpeg is available
    var isFFmpegAvailable: Bool {
        return ffmpegPath != nil && ffprobePath != nil
    }

    /// Convert any audio/video file to whisper-compatible WAV format (16kHz, mono, 16-bit PCM)
    /// - Parameters:
    ///   - inputPath: Path to the input audio/video file
    ///   - outputPath: Path for the output WAV file
    ///   - progressHandler: Optional callback for progress updates
    /// - Throws: AudioPreprocessingError if conversion fails
    func convertToWhisperFormat(inputPath: String, outputPath: String, progressHandler: ((Double) -> Void)? = nil) throws {
        guard isFFmpegAvailable else {
            throw AudioPreprocessingError.ffmpegNotFound
        }

        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw AudioPreprocessingError.inputFileNotFound(inputPath)
        }

        let process = Process()
        guard let ffmpegPath else {
            throw AudioPreprocessingError.ffmpegNotFound
        }

        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-i", inputPath,
            "-ar", "16000",      // 16kHz sample rate
            "-ac", "1",          // Mono channel
            "-c:a", "pcm_s16le", // 16-bit PCM
            "-f", "wav",         // WAV format
            "-y",                // Overwrite output
            outputPath
        ]

        // Set up pipe for error output
        let errorPipe = Pipe()
        process.standardError = errorPipe

        // Set up progress monitoring
        if let progressHandler = progressHandler {
            let outputPipe = Pipe()
            process.standardOutput = outputPipe

            // Monitor output for progress
            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if let output = String(data: data, encoding: .utf8) {
                    // Parse ffmpeg progress output
                    if let _ = output.range(of: "time=(\\d{2}):(\\d{2}):(\\d{2}\\.\\d{2})", options: .regularExpression) {
                        // Extract time and calculate progress (simplified)
                        progressHandler(0.5) // Placeholder progress
                    }
                }
            }
        }

        do {
            try process.run()
            process.waitUntilExit()

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw AudioPreprocessingError.conversionFailed(errorOutput)
            }

            guard FileManager.default.fileExists(atPath: outputPath) else {
                throw AudioPreprocessingError.outputFileNotCreated
            }

            progressHandler?(1.0)

        } catch {
            throw AudioPreprocessingError.processFailed(error)
        }
    }

    /// Get audio duration using ffprobe
    func getAudioDuration(path: String) throws -> TimeInterval {
        guard isFFmpegAvailable else {
            throw AudioPreprocessingError.ffmpegNotFound
        }

        let process = Process()
        guard let ffprobePath else {
            throw AudioPreprocessingError.ffmpegNotFound
        }

        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"

        return Double(output) ?? 0.0
    }

    /// Get audio file information
    func getAudioInfo(path: String) throws -> AudioInfo {
        guard isFFmpegAvailable else {
            throw AudioPreprocessingError.ffmpegNotFound
        }

        let process = Process()
        guard let ffprobePath else {
            throw AudioPreprocessingError.ffmpegNotFound
        }

        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = [
            "-v", "error",
            "-show_format",
            "-show_streams",
            "-of", "json",
            path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        // Parse JSON output (simplified)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let format = json["format"] as? [String: Any] else {
            return AudioInfo(duration: 0, format: "unknown", sampleRate: 0, channels: 0)
        }

        let duration = Double(format["duration"] as? String ?? "0") ?? 0
        let formatName = format["format_name"] as? String ?? "unknown"

        // Get sample rate from streams
        var sampleRate = 0
        var channels = 0
        if let streams = json["streams"] as? [[String: Any]] {
            for stream in streams {
                if stream["codec_type"] as? String == "audio" {
                    sampleRate = Int(stream["sample_rate"] as? String ?? "0") ?? 0
                    channels = Int(stream["channels"] as? String ?? "0") ?? 0
                    break
                }
            }
        }

        return AudioInfo(
            duration: duration,
            format: formatName,
            sampleRate: sampleRate,
            channels: channels
        )
    }

    /// Clean up temporary WAV file
    func cleanupTempFile(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func executablePath(named name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]

        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return match
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        var environment = ProcessInfo.processInfo.environment
        let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "\(fallbackPath):\(environment["PATH"] ?? "")"
        process.environment = environment

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

/// Audio file information
struct AudioInfo {
    let duration: TimeInterval
    let format: String
    let sampleRate: Int
    let channels: Int

    var durationString: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// Errors that can occur during audio preprocessing
enum AudioPreprocessingError: LocalizedError {
    case ffmpegNotFound
    case inputFileNotFound(String)
    case conversionFailed(String)
    case outputFileNotCreated
    case processFailed(Error)

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "FFmpeg 未找到。请安装 ffmpeg：brew install ffmpeg"
        case .inputFileNotFound(let path):
            return "输入文件未找到：\(path)"
        case .conversionFailed(let details):
            return "音频转换失败：\(details)"
        case .outputFileNotCreated:
            return "输出文件未创建"
        case .processFailed(let error):
            return "进程执行失败：\(error.localizedDescription)"
        }
    }
}
