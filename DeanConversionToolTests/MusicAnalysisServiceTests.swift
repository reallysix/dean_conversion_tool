import XCTest
@testable import DeanConversionTool

final class MusicAnalysisServiceTests: XCTestCase {
    func testMergesRepeatedMatchesAndRejectsLowScores() async {
        let samples = [
            sample(path: "/tmp/1.mp3", startTime: 10),
            sample(path: "/tmp/2.mp3", startTime: 40),
            sample(path: "/tmp/3.mp3", startTime: 70),
        ]
        let accepted = MusicMatch(
            providerRecordingID: "acr-123",
            title: "Song",
            artist: "Artist",
            album: nil,
            confidence: 96,
            playOffset: 1
        )
        let lowScore = MusicMatch(
            providerRecordingID: "acr-low",
            title: "Wrong",
            artist: nil,
            album: nil,
            confidence: 69,
            playOffset: nil
        )
        let service = MusicAnalysisService(
            sampleProducer: FakeSampleProducer(result: samples),
            provider: FakeMusicProvider(responses: [
                .success([accepted]),
                .success([accepted]),
                .success([lowScore]),
            ])
        )

        let analysis = await service.analyze(
            sourceURL: URL(string: "https://example.com/video")!,
            audioURL: URL(fileURLWithPath: "/tmp/source.m4a"),
            duration: 90,
            transcriptSegments: [],
            metadata: metadata(),
            mode: .quick
        )

        XCTAssertEqual(analysis.tracks.count, 1)
        XCTAssertEqual(analysis.tracks[0].providerRecordingID, "acr-123")
        XCTAssertEqual(analysis.tracks[0].startTime, 11)
        XCTAssertEqual(analysis.tracks[0].endTime, 48)
        XCTAssertEqual(analysis.unmatchedSampleCount, 1)
        XCTAssertEqual(analysis.outcome, .completed)
        XCTAssertEqual(analysis.submittedSampleCount, 3)
    }

    func testPlatformMetadataCreatesUntimedTrack() async {
        let service = MusicAnalysisService(
            sampleProducer: FakeSampleProducer(result: []),
            provider: nil
        )

        let analysis = await service.analyze(
            sourceURL: URL(string: "https://www.douyin.com/video/1")!,
            audioURL: URL(fileURLWithPath: "/tmp/source.m4a"),
            duration: 30,
            transcriptSegments: [],
            metadata: OnlineVideoMetadata(
                title: "Video",
                platform: "抖音",
                track: "Platform Song",
                artist: "Platform Artist"
            ),
            mode: .off
        )

        let track = analysis.tracks.first
        XCTAssertEqual(track?.title, "Platform Song")
        XCTAssertEqual(track?.artist, "Platform Artist")
        XCTAssertEqual(track?.source, .platformMetadata)
        XCTAssertNil(track?.startTime)
        XCTAssertNil(track?.endTime)
    }

    func testMissingProviderPreservesPlatformResultAndAddsWarning() async {
        let service = MusicAnalysisService(
            sampleProducer: FakeSampleProducer(result: []),
            provider: nil
        )

        let analysis = await service.analyze(
            sourceURL: URL(string: "https://example.com/video")!,
            audioURL: URL(fileURLWithPath: "/tmp/source.m4a"),
            duration: 30,
            transcriptSegments: [],
            metadata: OnlineVideoMetadata(
                title: "Video",
                platform: "公开网页视频",
                track: "Known Song",
                artist: nil
            ),
            mode: .quick
        )

        XCTAssertEqual(analysis.tracks.map(\.title), ["Known Song"])
        XCTAssertNotNil(analysis.warning)
        XCTAssertEqual(analysis.outcome, .notConfigured)
        XCTAssertEqual(analysis.submittedSampleCount, 0)
    }

    func testProviderErrorDoesNotDiscardSuccessfulMatches() async {
        let success = MusicMatch(
            providerRecordingID: "acr-success",
            title: "Found",
            artist: nil,
            album: nil,
            confidence: 90,
            playOffset: nil
        )
        let service = MusicAnalysisService(
            sampleProducer: FakeSampleProducer(result: [
                sample(path: "/tmp/1.mp3", startTime: 0),
                sample(path: "/tmp/2.mp3", startTime: 20),
            ]),
            provider: FakeMusicProvider(responses: [
                .success([success]),
                .failure(FakeError.failed),
            ])
        )

        let analysis = await service.analyze(
            sourceURL: URL(string: "https://example.com/video")!,
            audioURL: URL(fileURLWithPath: "/tmp/source.m4a"),
            duration: 30,
            transcriptSegments: [],
            metadata: metadata(),
            mode: .quick
        )

        XCTAssertEqual(analysis.tracks.map(\.title), ["Found"])
        XCTAssertEqual(analysis.unmatchedSampleCount, 1)
        XCTAssertNotNil(analysis.warning)
        XCTAssertEqual(analysis.outcome, .partialFailure)
        XCTAssertEqual(analysis.submittedSampleCount, 2)
    }

    func testAllProviderCallsFailWithFailedOutcome() async {
        let service = MusicAnalysisService(
            sampleProducer: FakeSampleProducer(result: [
                sample(path: "/tmp/1.mp3", startTime: 0),
                sample(path: "/tmp/2.mp3", startTime: 20),
            ]),
            provider: FakeMusicProvider(responses: [
                .failure(FakeError.failed),
                .failure(FakeError.failed),
            ])
        )

        let analysis = await service.analyze(
            sourceURL: URL(string: "https://example.com/video")!,
            audioURL: URL(fileURLWithPath: "/tmp/source.m4a"),
            duration: 30,
            transcriptSegments: [],
            metadata: metadata(),
            mode: .quick
        )

        XCTAssertEqual(analysis.outcome, .failed)
        XCTAssertEqual(analysis.submittedSampleCount, 2)
    }

    private func sample(path: String, startTime: TimeInterval) -> MusicAudioSample {
        MusicAudioSample(
            id: UUID(),
            audioURL: URL(fileURLWithPath: path),
            startTime: startTime,
            duration: 8
        )
    }

    private func metadata() -> OnlineVideoMetadata {
        OnlineVideoMetadata(
            title: "Video",
            platform: "公开网页视频",
            track: nil,
            artist: nil
        )
    }
}

private final class FakeSampleProducer: MusicSampleProducing {
    let result: [MusicAudioSample]

    init(result: [MusicAudioSample]) {
        self.result = result
    }

    func samples(
        audioURL: URL,
        duration: TimeInterval,
        transcriptSegments: [TranscriptSegment],
        mode: MusicScanMode
    ) throws -> [MusicAudioSample] {
        result
    }

    func cleanup(samples: [MusicAudioSample]) {}
}

private final class FakeMusicProvider: MusicRecognitionProvider {
    let name = "Fake"
    private var responses: [Result<[MusicMatch], Error>]

    init(responses: [Result<[MusicMatch], Error>]) {
        self.responses = responses
    }

    func recognize(sample: MusicAudioSample) async throws -> [MusicMatch] {
        try responses.removeFirst().get()
    }
}

private enum FakeError: Error {
    case failed
}
