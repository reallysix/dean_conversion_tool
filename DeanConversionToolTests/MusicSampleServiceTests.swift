import XCTest
@testable import DeanConversionTool

final class MusicSampleServiceTests: XCTestCase {
    func testQuickModeCreatesAtMostThreeWindows() {
        let windows = MusicSamplePlanner().windows(
            duration: 180,
            transcriptSegments: [],
            mode: .quick
        )

        XCTAssertEqual(windows.count, 3)
        XCTAssertTrue(windows.allSatisfy { $0.duration == 8 })
    }

    func testDeepModeUsesFortyFiveSecondBucketsAndCapsAtTen() {
        let windows = MusicSamplePlanner().windows(
            duration: 900,
            transcriptSegments: [],
            mode: .deep
        )

        XCTAssertEqual(windows.count, 10)
    }

    func testPlannerPrefersLowerSpeechOverlap() {
        let speech = [
            TranscriptSegment(startTime: 0, endTime: 8, text: "speech"),
            TranscriptSegment(startTime: 22, endTime: 30, text: "speech"),
        ]
        let windows = MusicSamplePlanner().windows(
            duration: 30,
            transcriptSegments: speech,
            mode: .quick
        )

        XCTAssertEqual(windows.first?.startTime, 2)
    }

    func testShortVideoProducesOneClampedWindow() {
        let windows = MusicSamplePlanner().windows(
            duration: 5,
            transcriptSegments: [],
            mode: .quick
        )

        XCTAssertEqual(windows, [MusicSampleWindow(startTime: 0, duration: 5)])
    }

    func testExtractsMP3SampleWhenFFmpegIsAvailable() throws {
        let service = MusicSampleService()
        guard service.isAvailable else {
            throw XCTSkip("FFmpeg is not installed")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "music-sample-test-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.wav")
        let process = Process()
        process.executableURL = URL(
            fileURLWithPath: try XCTUnwrap(service.ffmpegExecutablePath)
        )
        process.arguments = [
            "-f", "lavfi",
            "-i", "sine=frequency=440:duration=12",
            "-ar", "16000",
            "-ac", "1",
            "-y", source.path,
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let samples = try service.samples(
            audioURL: source,
            duration: 12,
            transcriptSegments: [],
            mode: .quick
        )
        defer { service.cleanup(samples: samples) }

        let sample = try XCTUnwrap(samples.first)
        XCTAssertEqual(sample.audioURL.pathExtension, "mp3")
        XCTAssertLessThanOrEqual(
            try Data(contentsOf: sample.audioURL).base64EncodedString().utf8.count,
            1_048_576
        )
    }
}
