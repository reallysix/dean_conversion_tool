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

    func testUpgradesXiaohongshuPlaybackURLToHTTPS() throws {
        let url = try XCTUnwrap(URL(
            string: "http://sns-bak-v6.xhscdn.com/stream/video.mp4"
        ))

        XCTAssertEqual(
            OnlineVideoPlaybackURL.normalized(url).absoluteString,
            "https://sns-bak-v6.xhscdn.com/stream/video.mp4"
        )
    }

    func testDoesNotUpgradeUnrelatedHTTPPlaybackURL() throws {
        let url = try XCTUnwrap(URL(
            string: "http://media.example.com/video.mp4"
        ))

        XCTAssertEqual(OnlineVideoPlaybackURL.normalized(url), url)
    }

    func testYouTubeBotChallengeIsNotReportedAsRestrictedVideo() {
        let message = """
        ERROR: [youtube] rsVZQfOIDfk: Sign in to confirm you’re not a bot.
        Use --cookies-from-browser or --cookies for the authentication.
        """

        XCTAssertEqual(
            OnlineVideoError.downloadFailed(message).localizedDescription,
            "在线视频下载失败：YouTube 要求验证当前访问不是机器人。请先在 Chrome 登录 YouTube，再到设置 → 功能 → 在线视频登录状态中选择“Chrome 登录状态”，然后重试。"
        )
    }
}
