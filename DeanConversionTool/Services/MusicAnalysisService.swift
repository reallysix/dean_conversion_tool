import Foundation

final class MusicAnalysisService {
    private let sampleProducer: MusicSampleProducing
    private let provider: MusicRecognitionProvider?

    init(
        sampleProducer: MusicSampleProducing,
        provider: MusicRecognitionProvider?
    ) {
        self.sampleProducer = sampleProducer
        self.provider = provider
    }

    func analyze(
        sourceURL: URL,
        audioURL: URL,
        duration: TimeInterval,
        transcriptSegments: [TranscriptSegment],
        metadata: OnlineVideoMetadata,
        mode: MusicScanMode,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async -> MusicAnalysis {
        let createdAt = Date()
        let platformTracks = platformTracks(from: metadata)

        guard mode != .off else {
            return MusicAnalysis(
                sourceURL: sourceURL,
                createdAt: createdAt,
                scanMode: mode,
                tracks: platformTracks,
                unmatchedSampleCount: 0,
                providerName: nil,
                warning: nil,
                outcome: .completed,
                submittedSampleCount: 0
            )
        }
        guard let provider else {
            return MusicAnalysis(
                sourceURL: sourceURL,
                createdAt: createdAt,
                scanMode: mode,
                tracks: platformTracks,
                unmatchedSampleCount: 0,
                providerName: nil,
                warning: "未配置讯飞音乐识别凭据，仅保留平台标注结果",
                outcome: .notConfigured,
                submittedSampleCount: 0
            )
        }

        let samples: [MusicAudioSample]
        do {
            samples = try sampleProducer.samples(
                audioURL: audioURL,
                duration: duration,
                transcriptSegments: transcriptSegments,
                mode: mode
            )
        } catch {
            return MusicAnalysis(
                sourceURL: sourceURL,
                createdAt: createdAt,
                scanMode: mode,
                tracks: platformTracks,
                unmatchedSampleCount: 0,
                providerName: provider.name,
                warning: "音乐样本提取失败：\(error.localizedDescription)",
                outcome: .failed,
                submittedSampleCount: 0
            )
        }
        defer { sampleProducer.cleanup(samples: samples) }

        var accumulators: [String: TrackAccumulator] = [:]
        var unmatchedSampleCount = 0
        var warnings: [String] = []

        for (index, sample) in samples.enumerated() {
            do {
                let matches = try await provider.recognize(sample: sample)
                let accepted = matches.filter { ($0.confidence ?? 0) >= 70 }
                if accepted.isEmpty {
                    unmatchedSampleCount += 1
                } else {
                    for match in accepted {
                        merge(
                            match: match,
                            sample: sample,
                            into: &accumulators
                        )
                    }
                }
            } catch {
                unmatchedSampleCount += 1
                if warnings.isEmpty {
                    warnings.append("部分音乐样本识别失败：\(error.localizedDescription)")
                }
            }
            onProgress?(index + 1, samples.count)
        }

        let providerTracks = accumulators.values.map(\.track)
        let tracks = mergePlatformTracks(
            platformTracks,
            with: providerTracks
        ).sorted(by: trackSort)
        let outcome: MusicAnalysisOutcome
        if warnings.isEmpty {
            outcome = .completed
        } else if providerTracks.isEmpty {
            outcome = .failed
        } else {
            outcome = .partialFailure
        }

        return MusicAnalysis(
            sourceURL: sourceURL,
            createdAt: createdAt,
            scanMode: mode,
            tracks: tracks,
            unmatchedSampleCount: unmatchedSampleCount,
            providerName: provider.name,
            warning: warnings.isEmpty ? nil : warnings.joined(separator: "；"),
            outcome: outcome,
            submittedSampleCount: samples.count
        )
    }

    private func platformTracks(from metadata: OnlineVideoMetadata) -> [RecognizedTrack] {
        guard let title = trimmed(metadata.track) else {
            return []
        }
        return [
            RecognizedTrack(
                id: UUID(),
                title: title,
                artist: trimmed(metadata.artist),
                album: nil,
                startTime: nil,
                endTime: nil,
                confidence: nil,
                source: .platformMetadata,
                providerRecordingID: nil
            ),
        ]
    }

    private func merge(
        match: MusicMatch,
        sample: MusicAudioSample,
        into accumulators: inout [String: TrackAccumulator]
    ) {
        let occurrenceStart = sample.startTime + max(0, match.playOffset ?? 0)
        let occurrenceEnd = sample.startTime + sample.duration

        if var existing = accumulators[match.providerRecordingID] {
            existing.startTime = min(existing.startTime, occurrenceStart)
            existing.endTime = max(existing.endTime, occurrenceEnd)
            existing.confidence = max(
                existing.confidence ?? 0,
                match.confidence ?? 0
            )
            accumulators[match.providerRecordingID] = existing
        } else {
            accumulators[match.providerRecordingID] = TrackAccumulator(
                id: UUID(),
                title: match.title,
                artist: match.artist,
                album: match.album,
                startTime: occurrenceStart,
                endTime: occurrenceEnd,
                confidence: match.confidence,
                providerRecordingID: match.providerRecordingID
            )
        }
    }

    private func mergePlatformTracks(
        _ platformTracks: [RecognizedTrack],
        with providerTracks: [RecognizedTrack]
    ) -> [RecognizedTrack] {
        var merged = providerTracks
        for platformTrack in platformTracks {
            let duplicate = providerTracks.contains { providerTrack in
                normalized(providerTrack.title) == normalized(platformTrack.title) &&
                normalized(providerTrack.artist) == normalized(platformTrack.artist)
            }
            if !duplicate {
                merged.append(platformTrack)
            }
        }
        return merged
    }

    private func trackSort(_ left: RecognizedTrack, _ right: RecognizedTrack) -> Bool {
        switch (left.startTime, right.startTime) {
        case let (leftStart?, rightStart?):
            return leftStart == rightStart
                ? left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
                : leftStart < rightStart
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
    }

    private func trimmed(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue?.isEmpty == false ? trimmedValue : nil
    }

    private func normalized(_ value: String?) -> String {
        guard let value else {
            return ""
        }
        let scalars = value.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        return String(String.UnicodeScalarView(scalars))
    }
}

private struct TrackAccumulator {
    let id: UUID
    let title: String
    let artist: String?
    let album: String?
    var startTime: TimeInterval
    var endTime: TimeInterval
    var confidence: Double?
    let providerRecordingID: String

    var track: RecognizedTrack {
        RecognizedTrack(
            id: id,
            title: title,
            artist: artist,
            album: album,
            startTime: startTime,
            endTime: endTime,
            confidence: confidence,
            source: .xfyunACRCloud,
            providerRecordingID: providerRecordingID
        )
    }
}
