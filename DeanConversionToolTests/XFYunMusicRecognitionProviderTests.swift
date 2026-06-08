import XCTest
@testable import DeanConversionTool

final class XFYunMusicRecognitionProviderTests: XCTestCase {
    func testBuildsExpectedMusicRecognitionRequest() throws {
        let sampleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("xfyun-request-\(UUID().uuidString).mp3")
        try Data([0x49, 0x44, 0x33]).write(to: sampleURL)
        defer { try? FileManager.default.removeItem(at: sampleURL) }

        let provider = XFYunMusicRecognitionProvider(
            credentials: XFYunCredentials(
                appID: "test-app",
                apiKey: "test-key",
                apiSecret: "test-secret"
            )
        )
        let request = try provider.makeRequest(
            sample: MusicAudioSample(
                id: UUID(),
                audioURL: sampleURL,
                startTime: 0,
                duration: 8
            ),
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let header = try XCTUnwrap(json["header"] as? [String: Any])
        let parameter = try XCTUnwrap(json["parameter"] as? [String: Any])
        let acrMusic = try XCTUnwrap(parameter["acr_music"] as? [String: Any])
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        let audio = try XCTUnwrap(payload["data"] as? [String: Any])

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(header["app_id"] as? String, "test-app")
        XCTAssertEqual(acrMusic["mode"] as? String, "music")
        XCTAssertEqual(audio["encoding"] as? String, "lame")
        XCTAssertEqual(audio["sample_rate"] as? Int, 16_000)
        XCTAssertEqual(audio["channels"] as? Int, 1)
        XCTAssertEqual(audio["bit_depth"] as? Int, 16)
        XCTAssertEqual(audio["status"] as? Int, 3)
        XCTAssertEqual(audio["frame_size"] as? Int, 0)
        XCTAssertEqual(audio["audio"] as? String, "SUQz")
    }

    func testParsesMusicMatchFromNestedResponse() throws {
        let response = Data("""
        {
          "header": {"code": 0, "message": "success", "sid": "sid-1"},
          "payload": {
            "output_text": {
              "encoding": "utf8",
              "compress": "raw",
              "format": "json",
              "status": 3,
              "seq": "0",
              "text": "eyJzdGF0dXMiOnsiY29kZSI6MCwibXNnIjoic3VjY2VzcyIsInZlcnNpb24iOiIxLjAifSwibWV0YWRhdGEiOnsibXVzaWMiOlt7ImFjcmlkIjoiYWNyLTEyMyIsInRpdGxlIjoiU29uZyIsImFydGlzdHMiOlt7Im5hbWUiOiJBcnRpc3QifV0sImFsYnVtIjp7Im5hbWUiOiJBbGJ1bSJ9LCJwbGF5X29mZnNldF9tcyI6MTI1MCwic2NvcmUiOjk2fV19fQ=="
            }
          }
        }
        """.utf8)
        let provider = XFYunMusicRecognitionProvider(
            credentials: XFYunCredentials(
                appID: "test-app",
                apiKey: "test-key",
                apiSecret: "test-secret"
            )
        )

        let matches = try provider.parseResponse(response)
        let match = try XCTUnwrap(matches.first)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(match.providerRecordingID, "acr-123")
        XCTAssertEqual(match.title, "Song")
        XCTAssertEqual(match.artist, "Artist")
        XCTAssertEqual(match.album, "Album")
        XCTAssertEqual(match.playOffset, 1.25)
        XCTAssertEqual(match.confidence, 96)
    }
}
