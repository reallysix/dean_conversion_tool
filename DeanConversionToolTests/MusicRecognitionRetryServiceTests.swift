import XCTest
@testable import DeanConversionTool

final class MusicRecognitionRetryServiceTests: XCTestCase {
    func testMissingCredentialsStopsBeforeDownload() async {
        let downloader = RetryFakeDownloader()
        let service = MusicRecognitionRetryService(
            credentialStore: RetryMemoryCredentialStore(credentials: nil),
            downloader: downloader,
            sampleProducer: RetryFakeSampleProducer(samples: []),
            providerFactory: { _ in
                RetryFakeMusicProvider(matches: [])
            }
        )

        do {
            _ = try await service.retry(
                sourceURL: URL(string: "https://example.com/video")!,
                transcript: transcript(),
                mode: .quick,
                cookieSource: .none
            )
            XCTFail("预期缺少凭据错误")
        } catch {
            XCTAssertEqual(
                error as? MusicRecognitionRetryError,
                .missingCredentials
            )
        }

        XCTAssertEqual(downloader.downloadCount, 0)
        XCTAssertEqual(downloader.cleanupCount, 0)
    }

    func testSuccessfulRetryDownloadsAnalyzesAndCleansUp() async throws {
        let downloader = RetryFakeDownloader()
        let sample = MusicAudioSample(
            id: UUID(),
            audioURL: URL(fileURLWithPath: "/tmp/sample.mp3"),
            startTime: 12,
            duration: 8
        )
        let match = MusicMatch(
            providerRecordingID: "acr-123",
            title: "Song",
            artist: "Artist",
            album: nil,
            confidence: 95,
            playOffset: 1
        )
        let service = MusicRecognitionRetryService(
            credentialStore: RetryMemoryCredentialStore(
                credentials: XFYunCredentials(
                    appID: "app",
                    apiKey: "key",
                    apiSecret: "secret"
                )
            ),
            downloader: downloader,
            sampleProducer: RetryFakeSampleProducer(samples: [sample]),
            providerFactory: { _ in
                RetryFakeMusicProvider(matches: [match])
            }
        )

        let result = try await service.retry(
            sourceURL: URL(string: "https://example.com/video")!,
            transcript: transcript(),
            mode: .quick,
            cookieSource: .none
        )

        XCTAssertEqual(downloader.downloadCount, 1)
        XCTAssertEqual(downloader.cleanupCount, 1)
        XCTAssertEqual(result.outcome, .completed)
        XCTAssertEqual(result.tracks.map(\.title), ["Song"])
        XCTAssertEqual(result.submittedSampleCount, 1)
    }

    private func transcript() -> Transcript {
        Transcript(
            sourceURL: URL(string: "https://example.com/video")!,
            sourceTitle: "Video",
            segments: [
                TranscriptSegment(startTime: 0, endTime: 3, text: "hello"),
            ],
            duration: 60
        )
    }
}

private final class RetryMemoryCredentialStore: XFYunCredentialStoring {
    let credentials: XFYunCredentials?

    init(credentials: XFYunCredentials?) {
        self.credentials = credentials
    }

    func load() throws -> XFYunCredentials? {
        credentials
    }

    func save(_ credentials: XFYunCredentials) throws {}

    func clear() throws {}
}

private final class RetryFakeDownloader: MusicRetryAudioDownloading {
    private(set) var downloadCount = 0
    private(set) var cleanupCount = 0

    func downloadAudio(
        from urlString: String,
        cookieSource: OnlineVideoCookieSource
    ) async throws -> OnlineVideoDownload {
        downloadCount += 1
        return OnlineVideoDownload(
            originalURL: URL(string: urlString)!,
            title: "Video",
            audioURL: URL(fileURLWithPath: "/tmp/source.m4a"),
            metadata: OnlineVideoMetadata(
                title: "Video",
                platform: "公开网页视频",
                track: nil,
                artist: nil
            )
        )
    }

    func cleanup(download: OnlineVideoDownload) {
        cleanupCount += 1
    }
}

private final class RetryFakeSampleProducer: MusicSampleProducing {
    let result: [MusicAudioSample]

    init(samples: [MusicAudioSample]) {
        result = samples
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

private final class RetryFakeMusicProvider: MusicRecognitionProvider {
    let name = "Fake"
    let matches: [MusicMatch]

    init(matches: [MusicMatch]) {
        self.matches = matches
    }

    func recognize(sample: MusicAudioSample) async throws -> [MusicMatch] {
        matches
    }
}
