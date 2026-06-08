import XCTest
@testable import DeanConversionTool

final class MusicAnalysisModelTests: XCTestCase {
    func testMusicAnalysisRoundTripsThroughJSON() throws {
        let track = RecognizedTrack(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Test Song",
            artist: "Test Artist",
            album: "Test Album",
            startTime: 12,
            endTime: 20,
            confidence: 96,
            source: .xfyunACRCloud,
            providerRecordingID: "acr-123"
        )
        let analysis = MusicAnalysis(
            sourceURL: URL(string: "https://www.bilibili.com/video/BV1")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            scanMode: .quick,
            tracks: [track],
            unmatchedSampleCount: 1,
            providerName: "讯飞 ACRCloud",
            warning: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(MusicAnalysis.self, from: encoder.encode(analysis))
        XCTAssertEqual(decoded, analysis)
        XCTAssertEqual(MusicScanMode.quick.maxSampleCount, 3)
        XCTAssertEqual(MusicScanMode.deep.maxSampleCount, 10)
    }

    func testOldMusicAnalysisJSONDefaultsToCompletedOutcome() throws {
        let data = """
        {
          "sourceURL": "https://example.com/video",
          "createdAt": "2026-06-08T08:00:00Z",
          "scanMode": "quick",
          "tracks": [],
          "unmatchedSampleCount": 0
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let analysis = try decoder.decode(MusicAnalysis.self, from: data)

        XCTAssertEqual(analysis.outcome, .completed)
        XCTAssertEqual(analysis.submittedSampleCount, 0)
    }
}
