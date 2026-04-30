import Foundation

/// Service for speaker diarization using pyannote.audio via Python subprocess
class SpeakerDiarizationService {
    private let pythonPath = "/opt/homebrew/bin/python3"
    private let scriptPath: String

    init() {
        // Get the path to the Python helper script
        let bundle = Bundle.main
        if let resourcePath = bundle.resourcePath {
            scriptPath = "\(resourcePath)/speaker_diarization.py"
        } else {
            // Fallback for development
            scriptPath = "/Users/olivia/MyObjects/2026Projects/dean_conversion_tool/PythonHelpers/speaker_diarization.py"
        }
    }

    /// Check if Python and required packages are available
    var isAvailable: Bool {
        guard FileManager.default.fileExists(atPath: pythonPath) else {
            return false
        }

        // Check if pyannote.audio is installed
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", "import pyannote.audio; print('ok')"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Perform speaker diarization on an audio file
    /// - Parameters:
    ///   - audioPath: Path to the audio file (WAV format recommended)
    ///   - numSpeakers: Optional number of speakers to detect
    ///   - progressHandler: Optional callback for progress updates
    /// - Returns: Array of SpeakerSegment
    /// - Throws: SpeakerDiarizationError if diarization fails
    func diarize(audioPath: String, numSpeakers: Int? = nil, progressHandler: ((String) -> Void)? = nil) throws -> [SpeakerSegment] {
        guard FileManager.default.fileExists(atPath: pythonPath) else {
            throw SpeakerDiarizationError.pythonNotFound
        }

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw SpeakerDiarizationError.scriptNotFound(scriptPath)
        }

        progressHandler?("Starting speaker diarization...")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath, audioPath]

        if let numSpeakers = numSpeakers {
            process.arguments?.append(contentsOf: ["--num_speakers", String(numSpeakers)])
        }

        // Set up pipes
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Monitor progress
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let errorOutput = String(data: data, encoding: .utf8), !errorOutput.isEmpty {
                progressHandler?("Processing: \(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            guard process.terminationStatus == 0 else {
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw SpeakerDiarizationError.diarizationFailed(errorOutput)
            }

            let output = String(data: outputData, encoding: .utf8) ?? "[]"
            return try parseDiarizationOutput(output)

        } catch {
            throw SpeakerDiarizationError.processFailed(error)
        }
    }

    /// Parse the JSON output from the Python script
    private func parseDiarizationOutput(_ output: String) throws -> [SpeakerSegment] {
        guard let data = output.data(using: .utf8) else {
            throw SpeakerDiarizationError.invalidOutput
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            guard let segments = json else {
                throw SpeakerDiarizationError.invalidOutput
            }

            return segments.compactMap { dict in
                guard let start = dict["start"] as? Double,
                      let end = dict["end"] as? Double,
                      let speaker = dict["speaker"] as? String else {
                    return nil
                }
                return SpeakerSegment(start: start, end: end, speaker: speaker)
            }
        } catch {
            throw SpeakerDiarizationError.parsingFailed(error)
        }
    }

    /// Merge diarization segments with transcript segments
    func mergeWithTranscript(transcriptSegments: [TranscriptSegment], diarizationSegments: [SpeakerSegment]) -> [TranscriptSegment] {
        return transcriptSegments.map { segment in
            var updatedSegment = segment

            // Find the best matching speaker segment
            let midTime = (segment.startTime + segment.endTime) / 2.0
            let matchingSpeaker = diarizationSegments.first { speakerSegment in
                midTime >= speakerSegment.start && midTime <= speakerSegment.end
            }

            updatedSegment.speaker = matchingSpeaker?.speaker
            return updatedSegment
        }
    }
}

/// Speaker segment from diarization
struct SpeakerSegment {
    let start: Double
    let end: Double
    let speaker: String

    var duration: Double {
        return end - start
    }
}

/// Errors that can occur during speaker diarization
enum SpeakerDiarizationError: LocalizedError {
    case pythonNotFound
    case scriptNotFound(String)
    case diarizationFailed(String)
    case processFailed(Error)
    case invalidOutput
    case parsingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Python not found. Please install Python 3"
        case .scriptNotFound(let path):
            return "Diarization script not found: \(path)"
        case .diarizationFailed(let details):
            return "Speaker diarization failed: \(details)"
        case .processFailed(let error):
            return "Process failed: \(error.localizedDescription)"
        case .invalidOutput:
            return "Invalid output from diarization script"
        case .parsingFailed(let error):
            return "Failed to parse diarization output: \(error.localizedDescription)"
        }
    }
}
