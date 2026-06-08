import Foundation

protocol MusicSampleProducing {
    func samples(
        audioURL: URL,
        duration: TimeInterval,
        transcriptSegments: [TranscriptSegment],
        mode: MusicScanMode
    ) throws -> [MusicAudioSample]

    func cleanup(samples: [MusicAudioSample])
}

struct MusicSamplePlanner {
    private let targetDuration: TimeInterval = 8

    func windows(
        duration: TimeInterval,
        transcriptSegments: [TranscriptSegment],
        mode: MusicScanMode
    ) -> [MusicSampleWindow] {
        guard duration > 0, mode != .off else {
            return []
        }

        let sampleDuration = min(targetDuration, duration)
        let buckets = bucketRanges(duration: duration, mode: mode)
        let maximumStart = max(0, duration - sampleDuration)
        var selectedStarts: [TimeInterval] = []

        for bucket in buckets {
            let centered = (bucket.lowerBound + bucket.upperBound - sampleDuration) / 2
            let candidates = [
                bucket.lowerBound,
                centered,
                bucket.upperBound - sampleDuration,
            ].map { min(max(0, $0), maximumStart) }

            guard let bestStart = candidates.min(by: { left, right in
                let leftOverlap = speechOverlap(
                    start: left,
                    duration: sampleDuration,
                    transcriptSegments: transcriptSegments
                )
                let rightOverlap = speechOverlap(
                    start: right,
                    duration: sampleDuration,
                    transcriptSegments: transcriptSegments
                )
                if leftOverlap == rightOverlap {
                    return left < right
                }
                return leftOverlap < rightOverlap
            }) else {
                continue
            }

            if !selectedStarts.contains(where: { abs($0 - bestStart) < 1 }) {
                selectedStarts.append(bestStart)
            }
        }

        return selectedStarts
            .sorted()
            .map { MusicSampleWindow(startTime: $0, duration: sampleDuration) }
    }

    private func bucketRanges(
        duration: TimeInterval,
        mode: MusicScanMode
    ) -> [ClosedRange<TimeInterval>] {
        switch mode {
        case .off:
            return []
        case .quick:
            let width = duration / Double(mode.maxSampleCount)
            return (0..<mode.maxSampleCount).map { index in
                let start = Double(index) * width
                let end = index == mode.maxSampleCount - 1
                    ? duration
                    : Double(index + 1) * width
                return start...end
            }
        case .deep:
            return stride(from: 0.0, to: duration, by: 45.0)
                .prefix(mode.maxSampleCount)
                .map { start in start...min(duration, start + 45) }
        }
    }

    private func speechOverlap(
        start: TimeInterval,
        duration: TimeInterval,
        transcriptSegments: [TranscriptSegment]
    ) -> TimeInterval {
        let end = start + duration
        return transcriptSegments.reduce(0) { total, segment in
            let overlap = max(
                0,
                min(end, segment.endTime) - max(start, segment.startTime)
            )
            return total + overlap
        }
    }
}

final class MusicSampleService: MusicSampleProducing {
    private let planner: MusicSamplePlanner
    private let resolvedFFmpegPath: String?

    init(planner: MusicSamplePlanner = MusicSamplePlanner()) {
        self.planner = planner
        self.resolvedFFmpegPath = Self.executablePath(named: "ffmpeg")
    }

    var isAvailable: Bool {
        ffmpegExecutablePath != nil
    }

    var ffmpegExecutablePath: String? {
        resolvedFFmpegPath
    }

    func samples(
        audioURL: URL,
        duration: TimeInterval,
        transcriptSegments: [TranscriptSegment],
        mode: MusicScanMode
    ) throws -> [MusicAudioSample] {
        let windows = planner.windows(
            duration: duration,
            transcriptSegments: transcriptSegments,
            mode: mode
        )
        guard !windows.isEmpty else {
            return []
        }
        guard let ffmpegExecutablePath else {
            throw MusicSampleError.ffmpegNotFound
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "dean-music-analysis-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        do {
            return try windows.enumerated().map { index, window in
                let outputURL = directory.appendingPathComponent(
                    String(format: "sample-%02d.mp3", index)
                )
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ffmpegExecutablePath)
                process.arguments = [
                    "-hide_banner",
                    "-loglevel", "error",
                    "-ss", Self.timeString(window.startTime),
                    "-t", Self.timeString(window.duration),
                    "-i", audioURL.path,
                    "-vn",
                    "-ac", "1",
                    "-ar", "16000",
                    "-sample_fmt", "s16",
                    "-codec:a", "libmp3lame",
                    "-b:a", "64k",
                    "-y", outputURL.path,
                ]

                let errorPipe = Pipe()
                process.standardOutput = Pipe()
                process.standardError = errorPipe
                try process.run()
                process.waitUntilExit()

                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? ""
                guard process.terminationStatus == 0 else {
                    throw MusicSampleError.extractionFailed(errorMessage)
                }

                let data = try Data(contentsOf: outputURL)
                guard !data.isEmpty else {
                    throw MusicSampleError.emptySample
                }
                guard data.base64EncodedString().utf8.count <= 1_048_576 else {
                    throw MusicSampleError.sampleTooLarge
                }

                return MusicAudioSample(
                    id: UUID(),
                    audioURL: outputURL,
                    startTime: window.startTime,
                    duration: window.duration
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func cleanup(samples: [MusicAudioSample]) {
        let directories = Set(samples.map { $0.audioURL.deletingLastPathComponent() })
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func timeString(_ value: TimeInterval) -> String {
        String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }

    private static func executablePath(named name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        if let match = candidates.first(
            where: { FileManager.default.isExecutableFile(atPath: $0) }
        ) {
            return match
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        var environment = ProcessInfo.processInfo.environment
        let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = "\(fallbackPath):\(environment["PATH"] ?? "")"
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }
            let output = String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == false ? output : nil
        } catch {
            return nil
        }
    }
}

enum MusicSampleError: LocalizedError {
    case ffmpegNotFound
    case extractionFailed(String)
    case emptySample
    case sampleTooLarge

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "未找到 FFmpeg，无法提取音乐识别样本"
        case .extractionFailed(let message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "音乐识别样本提取失败" : "音乐识别样本提取失败：\(detail)"
        case .emptySample:
            return "音乐识别样本为空"
        case .sampleTooLarge:
            return "音乐识别样本超过 1 MiB 限制"
        }
    }
}
