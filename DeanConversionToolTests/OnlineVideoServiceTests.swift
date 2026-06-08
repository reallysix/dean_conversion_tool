import XCTest
@testable import DeanConversionTool

final class OnlineVideoServiceTests: XCTestCase {
    func testParsesPlatformMusicMetadata() throws {
        let data = Data("""
        {
          "title": "Video title",
          "webpage_url": "https://www.douyin.com/video/123",
          "extractor_key": "Douyin",
          "track": "Platform Song",
          "artist": "Platform Artist"
        }
        """.utf8)

        let metadata = try OnlineVideoMetadataParser.parse(data)

        XCTAssertEqual(metadata.title, "Video title")
        XCTAssertEqual(metadata.platform, "抖音")
        XCTAssertEqual(metadata.track, "Platform Song")
        XCTAssertEqual(metadata.artist, "Platform Artist")
    }

    func testChromeCookieArgumentsAreOptIn() {
        XCTAssertEqual(OnlineVideoCookieSource.none.ytDLPArguments, [])
        XCTAssertEqual(
            OnlineVideoCookieSource.chrome.ytDLPArguments,
            ["--cookies-from-browser", "chrome"]
        )
    }

    func testRecognizesXiaohongshuPlatform() throws {
        let data = Data("""
        {
          "title": "Note",
          "webpage_url": "https://www.xiaohongshu.com/explore/123",
          "extractor_key": "XiaoHongShu"
        }
        """.utf8)

        XCTAssertEqual(try OnlineVideoMetadataParser.parse(data).platform, "小红书")
    }
}
