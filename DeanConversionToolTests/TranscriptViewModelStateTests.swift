import XCTest
@testable import DeanConversionTool

@MainActor
final class TranscriptViewModelStateTests: XCTestCase {
    func testResetTranscriptNavigationStateClearsPreviousFilterAndSelection() {
        let viewModel = TranscriptViewModel()
        let segment = TranscriptSegment(
            startTime: 0,
            endTime: 2,
            text: "新的文稿内容"
        )
        viewModel.transcript = Transcript(
            sourceURL: URL(string: "https://example.com/video")!,
            segments: [segment],
            duration: 2
        )
        viewModel.searchText = "旧关键词"
        viewModel.selectionManager.selectAll([segment.id])
        XCTAssertTrue(viewModel.filteredSegments.isEmpty)

        viewModel.resetTranscriptNavigationState()

        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertTrue(viewModel.selectionManager.selectedIDs.isEmpty)
        XCTAssertEqual(viewModel.filteredSegments.map(\.id), [segment.id])
    }

    func testManualMusicRecognitionDefaultsToQuickForOnlineTranscript() {
        let viewModel = TranscriptViewModel()
        viewModel.transcript = Transcript(
            sourceURL: URL(string: "https://example.com/video")!,
            segments: [],
            duration: 60
        )
        viewModel.musicScanMode = .off

        XCTAssertTrue(viewModel.canRecognizeMusicForCurrentTranscript)
        XCTAssertEqual(viewModel.manualMusicRecognitionMode, .quick)
    }

    func testManualMusicRecognitionIsUnavailableForLocalTranscript() {
        let viewModel = TranscriptViewModel()
        viewModel.transcript = Transcript(
            sourceURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            segments: [],
            duration: 60
        )

        XCTAssertFalse(viewModel.canRecognizeMusicForCurrentTranscript)
    }

    func testOnlineVideoInputStateExtractsURLFromSharedText() {
        let viewModel = TranscriptViewModel()
        viewModel.onlineVideoURL = """
        专家预言金融危机，普通人怎么自救？ http://xhslink.com/o/JjNOWnHrJJ 复制后打开【小红书】查看笔记！
        """

        let state = viewModel.onlineVideoInputState

        XCTAssertEqual(viewModel.onlineVideoURL, "http://xhslink.com/o/JjNOWnHrJJ")
        XCTAssertTrue(state.isReady)
        XCTAssertEqual(state.platformName, "小红书")
        XCTAssertEqual(state.normalizedURLString, "http://xhslink.com/o/JjNOWnHrJJ")
    }
}
