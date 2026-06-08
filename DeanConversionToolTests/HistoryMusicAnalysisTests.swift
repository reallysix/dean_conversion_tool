import XCTest
@testable import DeanConversionTool

final class HistoryMusicAnalysisTests: XCTestCase {
    func testOldProjectOutputsDecodeWithoutMusicField() throws {
        let data = Data("""
        {
          "transcriptJSON": "transcript.json",
          "subtitlesSRT": "subtitles.srt",
          "transcriptTXT": "transcript.txt",
          "transcriptMarkdown": "transcript.md"
        }
        """.utf8)

        let outputs = try JSONDecoder().decode(ProjectOutputs.self, from: data)
        XCTAssertNil(outputs.musicAnalysisJSON)
    }

    func testSavesAndLoadsMusicAnalysis() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryProjectStore(
            fileManager: .default,
            projectsRootURL: root
        )
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transcript = Transcript(
            sourceURL: URL(string: "https://example.com/video")!,
            sourceTitle: "Video",
            createdAt: createdAt,
            segments: [
                TranscriptSegment(startTime: 0, endTime: 1, text: "hello"),
            ],
            duration: 60
        )
        let analysis = MusicAnalysis(
            sourceURL: transcript.sourceURL,
            createdAt: createdAt,
            scanMode: .quick,
            tracks: [],
            unmatchedSampleCount: 1,
            providerName: "讯飞 ACRCloud",
            warning: nil
        )

        let project = try store.saveTranscriptProject(
            transcript: transcript,
            sourceType: .onlineVideo,
            musicAnalysis: analysis
        )

        let musicURL = try XCTUnwrap(project.musicAnalysisURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: musicURL.path))
        XCTAssertEqual(try store.loadMusicAnalysis(for: project), analysis)
    }

    func testTXTExportContainsTrackDetails() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let outputURL = directory.appendingPathComponent("music.txt")

        try MusicExportService().export(
            analysis: analysis(),
            format: .txt,
            outputURL: outputURL
        )

        let content = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(content.contains("[00:12-00:20]"))
        XCTAssertTrue(content.contains("Song - Artist"))
        XCTAssertTrue(content.contains("置信度 96"))
        XCTAssertTrue(content.contains("讯飞 ACRCloud"))
    }

    func testJSONExportRoundTrips() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let outputURL = directory.appendingPathComponent("music.json")
        let expected = analysis()

        try MusicExportService().export(
            analysis: expected,
            format: .json,
            outputURL: outputURL
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(
            try decoder.decode(MusicAnalysis.self, from: Data(contentsOf: outputURL)),
            expected
        )
    }

    func testUpdatesMusicAnalysisWithoutCreatingAnotherProject() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryProjectStore(
            fileManager: .default,
            projectsRootURL: root
        )
        let transcript = Transcript(
            sourceURL: URL(string: "https://example.com/video")!,
            sourceTitle: "Video",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            segments: [
                TranscriptSegment(startTime: 0, endTime: 1, text: "hello"),
            ],
            duration: 60
        )
        let project = try store.saveTranscriptProject(
            transcript: transcript,
            sourceType: .onlineVideo
        )
        let expected = analysis()

        let updated = try store.updateMusicAnalysis(expected, for: project)

        XCTAssertEqual(try store.loadProjects().count, 1)
        XCTAssertEqual(updated.id, project.id)
        XCTAssertEqual(updated.outputs.musicAnalysisJSON, "music-analysis.json")
        XCTAssertEqual(try store.loadMusicAnalysis(for: updated), expected)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "history-music-test-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func analysis() -> MusicAnalysis {
        MusicAnalysis(
            sourceURL: URL(string: "https://example.com/video")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            scanMode: .quick,
            tracks: [
                RecognizedTrack(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    title: "Song",
                    artist: "Artist",
                    album: "Album",
                    startTime: 12,
                    endTime: 20,
                    confidence: 96,
                    source: .xfyunACRCloud,
                    providerRecordingID: "acr-123"
                ),
            ],
            unmatchedSampleCount: 0,
            providerName: "讯飞 ACRCloud",
            warning: nil
        )
    }
}
