# Background Music Recognition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional quick and deep background-music recognition to the online-video transcription flow using platform metadata first and iFlytek ACRCloud as the development provider.

**Architecture:** Keep music analysis separate from transcript data. `OnlineVideoService` returns platform music metadata, `MusicSampleService` selects and extracts short MP3 samples, and `MusicAnalysisService` coordinates a replaceable `MusicRecognitionProvider`. Development builds call iFlytek directly with Keychain credentials; a future commercial build can replace only the provider with a backend proxy.

**Tech Stack:** Swift 5, SwiftUI, Foundation `URLSession`, CryptoKit HMAC-SHA256, Security Keychain, FFmpeg, yt-dlp, XcodeGen, XCTest.

---

## File Map

Create:

- `DeanConversionTool/Models/MusicAnalysis.swift`: scan modes, provider-neutral music result models, sample and match types.
- `DeanConversionTool/Services/XFYunCredentialStore.swift`: iFlytek credential value and Keychain persistence.
- `DeanConversionTool/Services/XFYunRequestSigner.swift`: deterministic iFlytek HMAC-SHA256 URL signing.
- `DeanConversionTool/Services/XFYunMusicRecognitionProvider.swift`: iFlytek request/response mapping behind `MusicRecognitionProvider`.
- `DeanConversionTool/Services/MusicSampleService.swift`: sample-window planning and FFmpeg extraction.
- `DeanConversionTool/Services/MusicAnalysisService.swift`: platform-result merging, provider calls, deduplication, warnings.
- `DeanConversionTool/Services/MusicExportService.swift`: JSON and TXT exports for music results.
- `DeanConversionTool/ViewModels/MusicRecognitionSettingsViewModel.swift`: Keychain settings state and validation.
- `DeanConversionTool/Views/MusicAnalysisViews.swift`: reusable music result rows and recognition-mode controls.
- `DeanConversionToolTests/MusicAnalysisModelTests.swift`
- `DeanConversionToolTests/OnlineVideoServiceTests.swift`
- `DeanConversionToolTests/XFYunRequestSignerTests.swift`
- `DeanConversionToolTests/XFYunMusicRecognitionProviderTests.swift`
- `DeanConversionToolTests/MusicSampleServiceTests.swift`
- `DeanConversionToolTests/MusicAnalysisServiceTests.swift`
- `DeanConversionToolTests/HistoryMusicAnalysisTests.swift`
- `DeanConversionToolTests/MusicRecognitionSettingsViewModelTests.swift`

Modify:

- `project.yml`: add the XCTest target and test action.
- `DeanConversionTool/Services/OnlineVideoService.swift`: JSON metadata, Chrome Cookie arguments, Xiaohongshu platform support.
- `DeanConversionTool/Models/HistoryProject.swift`: optional music-analysis output.
- `DeanConversionTool/Services/HistoryProjectStore.swift`: save/load music analysis.
- `DeanConversionTool/ViewModels/TranscriptViewModel.swift`: pipeline state, analysis orchestration, history restore, exports.
- `DeanConversionTool/Views/ContentView.swift`: recognition-mode picker in the online-video panel.
- `DeanConversionTool/Views/PropertiesPanel.swift`: music results, warnings, exports.
- `DeanConversionTool/Views/SettingsView.swift`: iFlytek credential controls and Chrome Cookie choice.
- `README.md`: Chinese feature, privacy, setup, and commercial migration documentation.
- `README_EN.md`: matching English documentation.

## Task 1: Add XCTest Support and Provider-Neutral Models

**Files:**

- Modify: `project.yml`
- Create: `DeanConversionTool/Models/MusicAnalysis.swift`
- Create: `DeanConversionToolTests/MusicAnalysisModelTests.swift`

- [ ] **Step 1: Add the test target and a failing model test**

Add this target after the application target in `project.yml`:

```yaml
  DeanConversionToolTests:
    type: bundle.unit-test
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: DeanConversionToolTests
    dependencies:
      - target: DeanConversionTool
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.dean.conversiontool.tests
        GENERATE_INFOPLIST_FILE: YES
        BUNDLE_LOADER: "$(TEST_HOST)"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Dean Conversion Tool.app/Contents/MacOS/Dean Conversion Tool"

schemes:
  DeanConversionTool:
    build:
      targets:
        DeanConversionTool: all
        DeanConversionToolTests: [test]
    test:
      targets:
        - DeanConversionToolTests
```

Create `DeanConversionToolTests/MusicAnalysisModelTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Generate the project and verify the test fails**

Run:

```bash
xcodegen generate
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because `RecognizedTrack`, `MusicAnalysis`, and `MusicScanMode` do not exist.

- [ ] **Step 3: Implement the provider-neutral models**

Create `DeanConversionTool/Models/MusicAnalysis.swift`:

```swift
import Foundation

enum MusicRecognitionSource: String, Codable, Equatable {
    case platformMetadata
    case xfyunACRCloud
    case backend
    case shazamKit

    var displayName: String {
        switch self {
        case .platformMetadata: return "平台标注"
        case .xfyunACRCloud: return "讯飞 ACRCloud"
        case .backend: return "在线识别"
        case .shazamKit: return "ShazamKit"
        }
    }
}

enum MusicScanMode: String, Codable, CaseIterable, Equatable {
    case off
    case quick
    case deep

    var displayName: String {
        switch self {
        case .off: return "关闭"
        case .quick: return "快速识别"
        case .deep: return "深度识别"
        }
    }

    var maxSampleCount: Int {
        switch self {
        case .off: return 0
        case .quick: return 3
        case .deep: return 10
        }
    }
}

struct RecognizedTrack: Identifiable, Codable, Equatable {
    let id: UUID
    let title: String
    let artist: String?
    let album: String?
    let startTime: TimeInterval?
    let endTime: TimeInterval?
    let confidence: Double?
    let source: MusicRecognitionSource
    let providerRecordingID: String?
}

struct MusicAnalysis: Codable, Equatable {
    let sourceURL: URL
    let createdAt: Date
    let scanMode: MusicScanMode
    let tracks: [RecognizedTrack]
    let unmatchedSampleCount: Int
    let providerName: String?
    let warning: String?
}

struct MusicSampleWindow: Equatable {
    let startTime: TimeInterval
    let duration: TimeInterval
}

struct MusicAudioSample: Equatable {
    let id: UUID
    let audioURL: URL
    let startTime: TimeInterval
    let duration: TimeInterval
}

struct MusicMatch: Equatable {
    let providerRecordingID: String
    let title: String
    let artist: String?
    let album: String?
    let confidence: Double?
    let playOffset: TimeInterval?
}

protocol MusicRecognitionProvider {
    var name: String { get }
    func recognize(sample: MusicAudioSample) async throws -> [MusicMatch]
}
```

- [ ] **Step 4: Run the model test**

Run:

```bash
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add project.yml DeanConversionTool/Models/MusicAnalysis.swift DeanConversionToolTests/MusicAnalysisModelTests.swift DeanConversionTool.xcodeproj
git commit -m "test: add music analysis model coverage"
```

## Task 2: Return Platform Music Metadata and Support Chrome Cookies

**Files:**

- Modify: `DeanConversionTool/Services/OnlineVideoService.swift`
- Create: `DeanConversionToolTests/OnlineVideoServiceTests.swift`

- [ ] **Step 1: Write failing metadata and Cookie argument tests**

Create `DeanConversionToolTests/OnlineVideoServiceTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:DeanConversionToolTests/OnlineVideoServiceTests
```

Expected: FAIL because the metadata parser and Cookie enum do not exist.

- [ ] **Step 3: Add metadata and Cookie types**

Add to `OnlineVideoService.swift`:

```swift
enum OnlineVideoCookieSource: String, CaseIterable {
    case none
    case chrome

    var displayName: String {
        switch self {
        case .none: return "不使用"
        case .chrome: return "Chrome"
        }
    }

    var ytDLPArguments: [String] {
        switch self {
        case .none: return []
        case .chrome: return ["--cookies-from-browser", "chrome"]
        }
    }
}

struct OnlineVideoMetadata: Equatable {
    let title: String
    let platform: String
    let track: String?
    let artist: String?
}

enum OnlineVideoMetadataParser {
    private struct Payload: Decodable {
        let title: String?
        let webpageURL: String?
        let extractorKey: String?
        let track: String?
        let artist: String?

        enum CodingKeys: String, CodingKey {
            case title
            case webpageURL = "webpage_url"
            case extractorKey = "extractor_key"
            case track
            case artist
        }
    }

    static func parse(_ data: Data) throws -> OnlineVideoMetadata {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return OnlineVideoMetadata(
            title: payload.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "在线视频",
            platform: platformName(extractorKey: payload.extractorKey, webpageURL: payload.webpageURL),
            track: payload.track?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            artist: payload.artist?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }
}
```

Add a private `String.nilIfEmpty` helper and platform mapping for YouTube, Bilibili, Douyin, TikTok, XiaoHongShu, and Vimeo.

Use this helper:

```swift
private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
```

Use this parser mapping:

```swift
private static func platformName(extractorKey: String?, webpageURL: String?) -> String {
    let source = "\(extractorKey ?? "") \(webpageURL ?? "")".lowercased()
    if source.contains("youtube") || source.contains("youtu.be") { return "YouTube" }
    if source.contains("bilibili") || source.contains("b23.tv") { return "B 站" }
    if source.contains("douyin") { return "抖音" }
    if source.contains("tiktok") { return "TikTok" }
    if source.contains("xiaohongshu") || source.contains("xhslink") { return "小红书" }
    if source.contains("vimeo") { return "Vimeo" }
    return "公开网页视频"
}
```

- [ ] **Step 4: Make downloads return metadata**

Change `OnlineVideoDownload`:

```swift
struct OnlineVideoDownload {
    let originalURL: URL
    let title: String
    let audioURL: URL
    let metadata: OnlineVideoMetadata
}
```

Change service entry points to accept `cookieSource: OnlineVideoCookieSource = .none`. Append `cookieSource.ytDLPArguments` before the source URL in both download and preview commands.

Add `--write-info-json` to the audio download command. After the process succeeds:

1. Find the downloaded audio file.
2. Find the `.info.json` file in the same temporary directory.
3. Parse it with `OnlineVideoMetadataParser`.
4. Use parsed metadata for the returned title and platform music fields.

If the info JSON is absent, return fallback metadata with the original URL as title and no music fields; do not fail a successful download.

- [ ] **Step 5: Improve login-facing errors**

When stderr contains `sign in`, `login`, or `cookies`, return:

```text
这个视频需要登录。请先在 Chrome 登录对应平台，再到设置中启用“Chrome 登录状态”。
```

- [ ] **Step 6: Run tests and build**

Run:

```bash
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:DeanConversionToolTests/OnlineVideoServiceTests
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: both commands PASS.

- [ ] **Step 7: Commit**

```bash
git add DeanConversionTool/Services/OnlineVideoService.swift DeanConversionToolTests/OnlineVideoServiceTests.swift
git commit -m "feat: capture online video music metadata"
```

## Task 3: Add Keychain Credentials and Deterministic iFlytek Signing

**Files:**

- Create: `DeanConversionTool/Services/XFYunCredentialStore.swift`
- Create: `DeanConversionTool/Services/XFYunRequestSigner.swift`
- Create: `DeanConversionToolTests/XFYunRequestSignerTests.swift`

- [ ] **Step 1: Write failing credential and signer tests**

Create `DeanConversionToolTests/XFYunRequestSignerTests.swift`:

```swift
import XCTest
@testable import DeanConversionTool

final class XFYunRequestSignerTests: XCTestCase {
    func testCredentialsRequireAllThreeValues() {
        XCTAssertFalse(XFYunCredentials(appID: "app", apiKey: "", apiSecret: "secret").isComplete)
        XCTAssertTrue(XFYunCredentials(appID: "app", apiKey: "key", apiSecret: "secret").isComplete)
    }

    func testSignerProducesExpectedAuthorization() throws {
        let signer = XFYunRequestSigner()
        let date = ISO8601DateFormatter().date(from: "2022-03-31T02:42:08Z")!
        let url = try signer.signedURL(
            baseURL: URL(string: "https://cn-east-1.api.xf-yun.com/v1/private/s29ebee0d")!,
            apiKey: "test-api-key",
            apiSecret: "test-api-secret",
            date: date
        )
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let values = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })

        XCTAssertEqual(values["host"], "cn-east-1.api.xf-yun.com")
        XCTAssertEqual(values["date"], "Thu, 31 Mar 2022 02:42:08 GMT")
        XCTAssertEqual(
            values["authorization"],
            "YXBpX2tleT0idGVzdC1hcGkta2V5IiwgYWxnb3JpdGhtPSJobWFjLXNoYTI1NiIsIGhlYWRlcnM9Imhvc3QgZGF0ZSByZXF1ZXN0LWxpbmUiLCBzaWduYXR1cmU9IjR2cnd4YVUzdmJLYnMyeWFobHJGd1c0RFlxUGVoWXl3dXFhWW5zODdBbzg9Ig=="
        )
    }
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:DeanConversionToolTests/XFYunRequestSignerTests
```

Expected: FAIL because credentials and signer do not exist.

- [ ] **Step 3: Implement credentials and Keychain storage**

Create `XFYunCredentialStore.swift` with:

```swift
import Foundation
import Security

struct XFYunCredentials: Codable, Equatable {
    let appID: String
    let apiKey: String
    let apiSecret: String

    var isComplete: Bool {
        !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

protocol XFYunCredentialStoring {
    func load() throws -> XFYunCredentials?
    func save(_ credentials: XFYunCredentials) throws
    func clear() throws
}
```

Implement `KeychainXFYunCredentialStore` using one generic-password item:

- Service: `com.dean.conversiontool.xfyun-acrcloud`
- Account: `credentials`
- Value: JSON-encoded `XFYunCredentials`
- Save: delete the existing item, then call `SecItemAdd`.
- Load: call `SecItemCopyMatching` with `kSecReturnData`.
- Clear: call `SecItemDelete`.
- Treat `errSecItemNotFound` as an empty store.
- Convert every other status to a localized `KeychainCredentialError`.

- [ ] **Step 4: Implement the signer**

Create `XFYunRequestSigner.swift`:

```swift
import CryptoKit
import Foundation

struct XFYunRequestSigner {
    func signedURL(
        baseURL: URL,
        apiKey: String,
        apiSecret: String,
        date: Date = Date()
    ) throws -> URL {
        guard let host = baseURL.host else { throw XFYunSigningError.invalidURL }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let dateString = formatter.string(from: date)

        let signatureOrigin = """
        host: \(host)
        date: \(dateString)
        POST \(baseURL.path) HTTP/1.1
        """
        let key = SymmetricKey(data: Data(apiSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(signatureOrigin.utf8), using: key)
        let signatureBase64 = Data(signature).base64EncodedString()
        let authorizationOrigin = """
        api_key="\(apiKey)", algorithm="hmac-sha256", headers="host date request-line", signature="\(signatureBase64)"
        """

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "authorization", value: Data(authorizationOrigin.utf8).base64EncodedString()),
            URLQueryItem(name: "date", value: dateString),
            URLQueryItem(name: "host", value: host)
        ]
        guard let url = components?.url else { throw XFYunSigningError.invalidURL }
        return url
    }
}
```

- [ ] **Step 5: Run the signer tests**

Run:

```bash
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:DeanConversionToolTests/XFYunRequestSignerTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add DeanConversionTool/Services/XFYunCredentialStore.swift DeanConversionTool/Services/XFYunRequestSigner.swift DeanConversionToolTests/XFYunRequestSignerTests.swift
git commit -m "feat: secure and sign music recognition credentials"
```

## Task 4: Implement the iFlytek ACRCloud Provider

**Files:**

- Create: `DeanConversionTool/Services/XFYunMusicRecognitionProvider.swift`
- Create: `DeanConversionToolTests/XFYunMusicRecognitionProviderTests.swift`

- [ ] **Step 1: Write failing request and response tests**

Create tests that:

1. Write `Data([0x49, 0x44, 0x33])` to a temporary `.mp3`.
2. Call an internal `makeRequest(sample:date:)`.
3. Decode the JSON body and assert:

```swift
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
XCTAssertEqual(audio["sample_rate"] as? Int, 16000)
XCTAssertEqual(audio["channels"] as? Int, 1)
XCTAssertEqual(audio["status"] as? Int, 3)
```

Add a response fixture:

```swift
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
```

Assert `parseResponse(response)` returns one `MusicMatch` with ID `acr-123`, title `Song`, artist `Artist`, album `Album`, offset `1.25`, and confidence `96`.

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```bash
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:DeanConversionToolTests/XFYunMusicRecognitionProviderTests
```

Expected: FAIL because the provider does not exist.

- [ ] **Step 3: Implement request construction**

Create `XFYunMusicRecognitionProvider` with:

```swift
final class XFYunMusicRecognitionProvider: MusicRecognitionProvider {
    let name = "讯飞 ACRCloud"

    private let endpoint = URL(string: "https://cn-east-1.api.xf-yun.com/v1/private/s29ebee0d")!
    private let credentials: XFYunCredentials
    private let session: URLSession
    private let signer: XFYunRequestSigner

    init(
        credentials: XFYunCredentials,
        session: URLSession = .shared,
        signer: XFYunRequestSigner = XFYunRequestSigner()
    ) {
        self.credentials = credentials
        self.session = session
        self.signer = signer
    }
}
```

Build a `Codable` body with:

```json
{
  "header": {"app_id": "...", "status": 3},
  "parameter": {
    "acr_music": {
      "mode": "music",
      "output_text": {"encoding": "utf8", "compress": "raw", "format": "json"}
    }
  },
  "payload": {
    "data": {
      "encoding": "lame",
      "sample_rate": 16000,
      "channels": 1,
      "bit_depth": 16,
      "status": 3,
      "audio": "<base64>",
      "frame_size": 0
    }
  }
}
```

Reject samples whose Base64 string exceeds `1_048_576` UTF-8 bytes.

- [ ] **Step 4: Implement response parsing**

Decode:

1. Outer `header.code`; nonzero throws `XFYunMusicRecognitionError.service`.
2. `payload.output_text.text` from Base64.
3. Inner `status.code`; nonzero throws `XFYunMusicRecognitionError.recognition`.
4. `metadata.music`, mapping:
   - `acrid`
   - `title`
   - joined artist names
   - album name
   - `play_offset_ms / 1000`
   - `score`

Return an empty array when `metadata.music` is absent.

- [ ] **Step 5: Implement the network call**

`recognize(sample:)` must:

1. Validate complete credentials.
2. Build the signed request.
3. Call `session.data(for:)`.
4. Require HTTP 2xx.
5. Return `parseResponse`.

Do not log credentials, the signed URL, request body, or raw audio.

- [ ] **Step 6: Run provider tests**

Run:

```bash
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:DeanConversionToolTests/XFYunMusicRecognitionProviderTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add DeanConversionTool/Services/XFYunMusicRecognitionProvider.swift DeanConversionToolTests/XFYunMusicRecognitionProviderTests.swift
git commit -m "feat: add iFlytek music recognition provider"
```

## Task 5: Plan and Extract Short Music Samples

**Files:**

- Create: `DeanConversionTool/Services/MusicSampleService.swift`
- Create: `DeanConversionToolTests/MusicSampleServiceTests.swift`

- [ ] **Step 1: Write failing sample-planning tests**

Create tests for:

```swift
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
        TranscriptSegment(startTime: 22, endTime: 30, text: "speech")
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
        .appendingPathComponent("music-sample-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let source = directory.appendingPathComponent("source.wav")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: service.ffmpegExecutablePath!)
    process.arguments = [
        "-f", "lavfi",
        "-i", "sine=frequency=440:duration=12",
        "-ar", "16000",
        "-ac", "1",
        "-y", source.path
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
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:DeanConversionToolTests/MusicSampleServiceTests
```

Expected: FAIL because planner and service do not exist.

- [ ] **Step 3: Implement deterministic window planning**

`MusicSamplePlanner` must:

- Use an 8-second target duration.
- Return no windows for `.off` or nonpositive duration.
- For `.quick`, divide the duration into three equal buckets.
- For `.deep`, create 45-second buckets and keep the first ten.
- For each bucket, evaluate bucket start, centered position, and bucket end minus sample duration.
- Clamp candidates to `0...max(0, duration - sampleDuration)`.
- Choose the candidate with the lowest overlap duration against transcript segments.
- Deduplicate candidates whose start times differ by less than one second.
- Return windows sorted by start time.

- [ ] **Step 4: Implement FFmpeg extraction**

Add:

```swift
protocol MusicSampleProducing {
    func samples(
        audioURL: URL,
        duration: TimeInterval,
        transcriptSegments: [TranscriptSegment],
        mode: MusicScanMode
    ) throws -> [MusicAudioSample]
    func cleanup(samples: [MusicAudioSample])
}
```

`MusicSampleService` uses the planner and runs FFmpeg once per window:

```text
ffmpeg
-ss <start>
-t <duration>
-i <source>
-vn
-ac 1
-ar 16000
-sample_fmt s16
-codec:a libmp3lame
-b:a 64k
-y <temporary.mp3>
```

After each extraction:

- Require a nonempty file.
- Require `Data(contentsOf: file).base64EncodedString().utf8.count <= 1_048_576`.
- Return `MusicAudioSample` with the matching start time and duration.
- On any failure, remove the temporary analysis directory before throwing.

Expose read-only testable properties:

```swift
var isAvailable: Bool { ffmpegExecutablePath != nil }
var ffmpegExecutablePath: String? { resolvedFFmpegPath }
```

- [ ] **Step 5: Run tests and perform one extraction smoke test**

Run:

```bash
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:DeanConversionToolTests/MusicSampleServiceTests
```

Expected: tests PASS; the integration test skips only when FFmpeg is unavailable.

- [ ] **Step 6: Commit**

```bash
git add DeanConversionTool/Services/MusicSampleService.swift DeanConversionToolTests/MusicSampleServiceTests.swift
git commit -m "feat: extract background music samples"
```

## Task 6: Coordinate Recognition and Merge Results

**Files:**

- Create: `DeanConversionTool/Services/MusicAnalysisService.swift`
- Create: `DeanConversionToolTests/MusicAnalysisServiceTests.swift`

- [ ] **Step 1: Write failing orchestration tests**

Create fake implementations:

```swift
final class FakeSampleProducer: MusicSampleProducing {
    let result: [MusicAudioSample]
    init(result: [MusicAudioSample]) { self.result = result }

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

final class FakeMusicProvider: MusicRecognitionProvider {
    let name = "Fake"
    private var responses: [Result<[MusicMatch], Error>]

    init(responses: [Result<[MusicMatch], Error>]) {
        self.responses = responses
    }

    func recognize(sample: MusicAudioSample) async throws -> [MusicMatch] {
        try responses.removeFirst().get()
    }
}
```

Add this merge test:

```swift
func testMergesRepeatedMatchesAndRejectsLowScores() async {
    let samples = [
        MusicAudioSample(id: UUID(), audioURL: URL(fileURLWithPath: "/tmp/1.mp3"), startTime: 10, duration: 8),
        MusicAudioSample(id: UUID(), audioURL: URL(fileURLWithPath: "/tmp/2.mp3"), startTime: 40, duration: 8),
        MusicAudioSample(id: UUID(), audioURL: URL(fileURLWithPath: "/tmp/3.mp3"), startTime: 70, duration: 8)
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
            .success([lowScore])
        ])
    )

    let analysis = await service.analyze(
        sourceURL: URL(string: "https://example.com/video")!,
        audioURL: URL(fileURLWithPath: "/tmp/source.m4a"),
        duration: 90,
        transcriptSegments: [],
        metadata: OnlineVideoMetadata(
            title: "Video",
            platform: "公开网页视频",
            track: nil,
            artist: nil
        ),
        mode: .quick
    )

    XCTAssertEqual(analysis.tracks.count, 1)
    XCTAssertEqual(analysis.tracks[0].providerRecordingID, "acr-123")
    XCTAssertEqual(analysis.tracks[0].startTime, 11)
    XCTAssertEqual(analysis.tracks[0].endTime, 48)
    XCTAssertEqual(analysis.unmatchedSampleCount, 1)
}
```

Also test these behaviors with separate test methods:

- Platform metadata becomes a `.platformMetadata` track with nil times.
- Two samples returning `acr-123` merge into one track spanning both samples.
- A score of `69` is rejected and increments `unmatchedSampleCount`.
- A nil provider preserves platform results and sets a missing-credentials warning.
- A provider error on one sample does not discard successful results from other samples.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:DeanConversionToolTests/MusicAnalysisServiceTests
```

Expected: FAIL because `MusicAnalysisService` does not exist.

- [ ] **Step 3: Implement analysis orchestration**

Create:

```swift
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
}
```

Add:

```swift
func analyze(
    sourceURL: URL,
    audioURL: URL,
    duration: TimeInterval,
    transcriptSegments: [TranscriptSegment],
    metadata: OnlineVideoMetadata,
    mode: MusicScanMode,
    onProgress: ((Int, Int) -> Void)? = nil
) async -> MusicAnalysis
```

Behavior:

1. Create a platform track when `metadata.track` is nonempty.
2. If mode is `.off`, return platform results without creating samples.
3. If provider is nil, return platform results with a credential warning.
4. Extract samples and always call `cleanup` with `defer`.
5. If sample extraction throws, return platform results with an extraction warning.
6. Query samples serially and invoke progress after each attempt.
7. Treat empty results and scores below 70 as unmatched.
8. Record provider errors as a warning and continue.
9. Merge provider tracks by `providerRecordingID`.
10. Merge platform and provider tracks when normalized title and artist match.
11. Sort timed results by start time, followed by untimed platform results.

For a provider result, estimate:

```swift
let occurrenceStart = sample.startTime + (match.playOffset ?? 0)
let occurrenceEnd = sample.startTime + sample.duration
```

Merged occurrences use the earliest start and latest end.

- [ ] **Step 4: Run orchestration tests**

Run:

```bash
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:DeanConversionToolTests/MusicAnalysisServiceTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add DeanConversionTool/Services/MusicAnalysisService.swift DeanConversionToolTests/MusicAnalysisServiceTests.swift
git commit -m "feat: coordinate and merge music recognition"
```

## Task 7: Persist and Export Music Analysis

**Files:**

- Modify: `DeanConversionTool/Models/HistoryProject.swift`
- Modify: `DeanConversionTool/Services/HistoryProjectStore.swift`
- Create: `DeanConversionTool/Services/MusicExportService.swift`
- Create: `DeanConversionToolTests/HistoryMusicAnalysisTests.swift`

- [ ] **Step 1: Write failing history and export tests**

Test:

1. Decoding an old `ProjectOutputs` JSON without `musicAnalysisJSON` yields nil.
2. Saving a project with `MusicAnalysis` creates `music-analysis.json`.
3. Loading that project returns the same analysis.
4. TXT export contains title, artist, formatted time, confidence, and source.
5. JSON export round-trips through `MusicAnalysis`.

Add the backward-compatibility test:

```swift
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
```

Add the save/load test:

```swift
func testSavesAndLoadsMusicAnalysis() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("history-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = HistoryProjectStore(fileManager: .default, projectsRootURL: root)
    let transcript = Transcript(
        sourceURL: URL(string: "https://example.com/video")!,
        sourceTitle: "Video",
        segments: [TranscriptSegment(startTime: 0, endTime: 1, text: "hello")],
        duration: 60
    )
    let analysis = MusicAnalysis(
        sourceURL: transcript.sourceURL,
        createdAt: transcript.createdAt,
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

    XCTAssertTrue(FileManager.default.fileExists(atPath: project.musicAnalysisURL!.path))
    XCTAssertEqual(try store.loadMusicAnalysis(for: project), analysis)
}
```

Use a temporary root:

```swift
let root = FileManager.default.temporaryDirectory
    .appendingPathComponent("history-test-\(UUID().uuidString)", isDirectory: true)
defer { try? FileManager.default.removeItem(at: root) }
let store = HistoryProjectStore(fileManager: .default, projectsRootURL: root)
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:DeanConversionToolTests/HistoryMusicAnalysisTests
```

Expected: FAIL because history and export support do not exist.

- [ ] **Step 3: Extend project outputs**

Change:

```swift
struct ProjectOutputs: Codable, Equatable {
    var transcriptJSON: String?
    var subtitlesSRT: String?
    var transcriptTXT: String?
    var transcriptMarkdown: String?
    var musicAnalysisJSON: String?
}
```

Add:

```swift
var musicAnalysisURL: URL? {
    guard let name = outputs.musicAnalysisJSON else { return nil }
    return projectURL.appendingPathComponent(name)
}
```

- [ ] **Step 4: Save and load analysis**

Change the store initializer:

```swift
init(
    fileManager: FileManager = .default,
    projectsRootURL: URL? = nil
) {
    self.fileManager = fileManager
    self.customProjectsRootURL = projectsRootURL
}
```

Add:

```swift
private let customProjectsRootURL: URL?

var projectsRootURL: URL {
    if let customProjectsRootURL {
        return customProjectsRootURL
    }
    let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return documentsURL.appendingPathComponent("DeanConversionTool/Projects", isDirectory: true)
}
```

Change `saveTranscriptProject` to accept `musicAnalysis: MusicAnalysis? = nil`. When present:

- Encode it with pretty-printed, sorted ISO-8601 JSON.
- Write `music-analysis.json`.
- Store the filename in `ProjectOutputs.musicAnalysisJSON`.

Add:

```swift
func loadMusicAnalysis(for project: HistoryProject) throws -> MusicAnalysis?
```

Return nil when no music file is recorded.

- [ ] **Step 5: Implement exports**

Create:

```swift
enum MusicExportFormat {
    case json
    case txt

    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .txt: return "txt"
        }
    }

    var displayName: String {
        switch self {
        case .json: return "音乐分析 JSON"
        case .txt: return "音乐列表 TXT"
        }
    }
}

final class MusicExportService {
    func export(
        analysis: MusicAnalysis,
        format: MusicExportFormat,
        outputURL: URL
    ) throws
}
```

TXT lines must use:

```text
[00:12-00:20] Song - Artist | 置信度 96 | 讯飞 ACRCloud
```

Use `--:--` for missing times and omit album/confidence fields when absent.

- [ ] **Step 6: Run tests**

Run:

```bash
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:DeanConversionToolTests/HistoryMusicAnalysisTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add DeanConversionTool/Models/HistoryProject.swift DeanConversionTool/Services/HistoryProjectStore.swift DeanConversionTool/Services/MusicExportService.swift DeanConversionToolTests/HistoryMusicAnalysisTests.swift
git commit -m "feat: persist and export music analysis"
```

## Task 8: Integrate Music Analysis into the Online Pipeline

**Files:**

- Modify: `DeanConversionTool/ViewModels/TranscriptViewModel.swift`

- [ ] **Step 1: Add published state**

Add:

```swift
@Published var musicScanMode: MusicScanMode = .off
@Published var musicAnalysis: MusicAnalysis?
@Published var musicAnalysisMessage: String?
@Published var musicAnalysisIsError = false
@Published var lastExportedMusicFileURL: URL?
```

Add services:

```swift
private let credentialStore: XFYunCredentialStoring = KeychainXFYunCredentialStore()
private let musicSampleService = MusicSampleService()
private let musicExportService = MusicExportService()
```

- [ ] **Step 2: Read the Cookie setting for every online operation**

Add:

```swift
private var onlineVideoCookieSource: OnlineVideoCookieSource {
    let raw = UserDefaults.standard.string(forKey: "onlineVideoCookieSource")
    return OnlineVideoCookieSource(rawValue: raw ?? "") ?? .none
}
```

Pass it to:

- `downloadAudio`
- `playableVideoURL`
- online-preview retries

- [ ] **Step 3: Run optional analysis after transcription**

In `processOnlineVideo`:

1. Clear previous music state when processing starts.
2. Download audio and metadata.
3. Complete transcription first.
4. If mode is not `.off`, load credentials.
5. Create `XFYunMusicRecognitionProvider` only when credentials are complete.
6. Create `MusicAnalysisService` with that optional provider.
7. Analyze with downloaded audio, transcript duration and segments, metadata, and selected mode.
8. Map music progress to `0.78...0.96`.
9. Set `musicAnalysis` and warning state.
10. Archive transcript and music analysis together.

`MusicAnalysisService` must convert sample extraction and provider errors into warnings. The ViewModel must not convert those warnings into a main pipeline failure. Show:

```text
文稿已完成，但背景音乐识别失败：<reason>
```

The transcript still archives successfully.

- [ ] **Step 4: Restore and clear music state**

`openProject` loads `historyStore.loadMusicAnalysis(for:)`.

`clearTranscript` resets:

- `musicAnalysis`
- `musicAnalysisMessage`
- `musicAnalysisIsError`
- `lastExportedMusicFileURL`

- [ ] **Step 5: Add music exports**

Add:

```swift
func exportMusicAnalysis(format: MusicExportFormat)
func revealLastExportedMusicFile()
```

Match the existing transcript export flow:

- Choose a directory with `NSOpenPanel`.
- Generate a unique `<title>_music-analysis.json` or `.txt`.
- Write with `MusicExportService`.
- Store status and reveal the file in Finder.

- [ ] **Step 6: Build and run all unit tests**

Run:

```bash
xcodegen generate
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add DeanConversionTool/ViewModels/TranscriptViewModel.swift
git commit -m "feat: run music analysis with online transcription"
```

## Task 9: Add Credential Settings and Music UI

**Files:**

- Create: `DeanConversionTool/ViewModels/MusicRecognitionSettingsViewModel.swift`
- Create: `DeanConversionTool/Views/MusicAnalysisViews.swift`
- Create: `DeanConversionToolTests/MusicRecognitionSettingsViewModelTests.swift`
- Modify: `DeanConversionTool/Views/SettingsView.swift`
- Modify: `DeanConversionTool/Views/ContentView.swift`
- Modify: `DeanConversionTool/Views/PropertiesPanel.swift`

- [ ] **Step 1: Write failing settings-model tests**

Use an in-memory `XFYunCredentialStoring` fake and test:

- Saving with any blank field sets an error and does not call the store.
- Saving three values trims whitespace and stores credentials.
- Loading existing credentials sets `isConfigured` but leaves all secret text fields empty.
- Clearing removes credentials and sets `isConfigured` false.

Use:

```swift
final class MemoryCredentialStore: XFYunCredentialStoring {
    var credentials: XFYunCredentials?
    var saveCount = 0

    func load() throws -> XFYunCredentials? { credentials }

    func save(_ credentials: XFYunCredentials) throws {
        self.credentials = credentials
        saveCount += 1
    }

    func clear() throws {
        credentials = nil
    }
}

@MainActor
func testSaveTrimsAndStoresCredentials() {
    let store = MemoryCredentialStore()
    let model = MusicRecognitionSettingsViewModel(store: store)
    model.appID = " app "
    model.apiKey = " key "
    model.apiSecret = " secret "

    model.save()

    XCTAssertEqual(
        store.credentials,
        XFYunCredentials(appID: "app", apiKey: "key", apiSecret: "secret")
    )
    XCTAssertEqual(store.saveCount, 1)
    XCTAssertTrue(model.isConfigured)
    XCTAssertEqual(model.apiSecret, "")
}
```

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```bash
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO -only-testing:DeanConversionToolTests/MusicRecognitionSettingsViewModelTests
```

Expected: FAIL because the settings model does not exist.

- [ ] **Step 3: Implement the settings model**

Create an `@MainActor ObservableObject` with:

```swift
@MainActor
final class MusicRecognitionSettingsViewModel: ObservableObject {
@Published var appID = ""
@Published var apiKey = ""
@Published var apiSecret = ""
@Published private(set) var isConfigured = false
@Published var statusMessage: String?
@Published var statusIsError = false

    private let store: XFYunCredentialStoring

    init(store: XFYunCredentialStoring = KeychainXFYunCredentialStore()) {
        self.store = store
        loadStatus()
    }

    func loadStatus() {
        do {
            isConfigured = try store.load()?.isComplete == true
            statusMessage = nil
            statusIsError = false
        } catch {
            isConfigured = false
            statusMessage = "读取凭证失败：\(error.localizedDescription)"
            statusIsError = true
        }
    }

    func save() {
        let credentials = XFYunCredentials(
            appID: appID.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            apiSecret: apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard credentials.isComplete else {
            statusMessage = "请完整填写 APPID、APIKey 和 APISecret。"
            statusIsError = true
            return
        }

        do {
            try store.save(credentials)
            appID = ""
            apiKey = ""
            apiSecret = ""
            isConfigured = true
            statusMessage = "讯飞识曲凭证已保存到钥匙串。"
            statusIsError = false
        } catch {
            statusMessage = "保存凭证失败：\(error.localizedDescription)"
            statusIsError = true
        }
    }

    func clear() {
        do {
            try store.clear()
            appID = ""
            apiKey = ""
            apiSecret = ""
            isConfigured = false
            statusMessage = "讯飞识曲凭证已清除。"
            statusIsError = false
        } catch {
            statusMessage = "清除凭证失败：\(error.localizedDescription)"
            statusIsError = true
        }
    }
}
```

After successful save, clear all three text fields so secrets are not left visible.

- [ ] **Step 4: Add the online recognition-mode control**

Create `MusicScanModePicker` in `MusicAnalysisViews.swift`:

```swift
Picker("背景音乐", selection: $mode) {
    ForEach(MusicScanMode.allCases, id: \.rawValue) { mode in
        Text(mode.displayName).tag(mode)
    }
}
.pickerStyle(.segmented)
```

In `ContentView`:

- Change the online subtitle to `YouTube、B 站、抖音、小红书等链接`.
- Place the picker between link status and the primary button.
- Show `快速最多 3 段，深度最多 10 段；音频样本会发送到讯飞。` when mode is enabled.

- [ ] **Step 5: Add settings controls**

In the feature settings panel:

- Add a “背景音乐识别” section.
- Show configured/not configured status.
- Use one `TextField` for APPID and `SecureField` for APIKey/APISecret.
- Add “保存凭证” and “清除凭证” buttons.
- Show the direct-call development warning.
- Add a picker bound to:

```swift
@AppStorage("onlineVideoCookieSource") private var onlineVideoCookieSource = OnlineVideoCookieSource.none.rawValue
```

Options are only `.none` and `.chrome`.

- [ ] **Step 6: Add music result views**

In `PropertiesPanel`, when `viewModel.musicAnalysis` exists:

- Add `PropertiesSection(title: "背景音乐")`.
- Display every track with title, artist, formatted time, source, and confidence.
- Display unmatched sample count.
- Display `musicAnalysis.warning`.
- Add “导出音乐 JSON” and “导出音乐 TXT”.
- Show export status and Finder reveal action.

When the transcript exists but music mode was off, do not show an empty music section.

- [ ] **Step 7: Run tests and build**

Run:

```bash
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

- [ ] **Step 8: Launch and visually verify**

Run:

```bash
open "$(find ~/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Debug/Dean Conversion Tool.app' -print -quit)"
```

Verify:

- Online panel fits at the minimum 1280x760 window size.
- Mode selector defaults to off.
- Enabled mode shows the upload notice.
- Settings never reveal stored credentials.
- Chrome login-state selection persists after closing settings.
- Music rows remain readable in the fixed-width properties panel.

- [ ] **Step 9: Commit**

```bash
git add DeanConversionTool/ViewModels/MusicRecognitionSettingsViewModel.swift DeanConversionTool/Views/MusicAnalysisViews.swift DeanConversionTool/Views/SettingsView.swift DeanConversionTool/Views/ContentView.swift DeanConversionTool/Views/PropertiesPanel.swift DeanConversionToolTests/MusicRecognitionSettingsViewModelTests.swift
git commit -m "feat: add music recognition controls and results"
```

## Task 10: Real-Service Test, Documentation, and Final Verification

**Files:**

- Modify: `README.md`
- Modify: `README_EN.md`

- [ ] **Step 1: Document setup and limitations**

Document:

- Quick and deep recognition modes.
- Platform metadata first, iFlytek fallback.
- iFlytek service registration and where to find APPID/APIKey/APISecret.
- The 8-second sample upload disclosure.
- Chrome Cookie opt-in behavior.
- No password or Cookie persistence.
- Development builds call iFlytek directly.
- Public commercial builds must use a backend proxy so provider secrets are not shipped in the app.
- Music recognition errors do not fail transcription.

- [ ] **Step 2: Run a real quick recognition test**

Prerequisites:

- Configure valid test credentials in Settings.
- Choose a public short video whose music is independently known.
- Select quick recognition.

Verify:

1. At most three samples are sent.
2. A track result or an explicit no-match warning appears.
3. The transcript still completes.
4. `music-analysis.json` is present in the history project.
5. Downloaded source audio and temporary samples are absent after completion.

Do not commit credentials, sample audio, Cookies, signed URLs, or service response dumps.

- [ ] **Step 3: Verify Chrome Cookie opt-in**

With a user-authorized video that requires login:

1. Confirm parsing fails with Cookie source set to none.
2. Log into the platform in Chrome.
3. Enable Chrome login state.
4. Confirm yt-dlp receives `--cookies-from-browser chrome`.
5. Confirm the app does not create a Cookie file in the repository, project history, or Application Support.

- [ ] **Step 4: Run all automated verification**

```bash
xcodegen generate
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -configuration Debug build CODE_SIGNING_ALLOWED=NO
./test_pipeline.sh
Scripts/check_dependencies.sh
git diff --check
```

Expected:

- Unit tests PASS.
- Debug build succeeds.
- Existing pipeline test passes on the configured machine.
- Dependency check remains unchanged because no new Homebrew dependency was added.
- `git diff --check` reports no whitespace errors.

- [ ] **Step 5: Inspect the final diff**

Run:

```bash
git status --short
git diff --stat
git diff -- project.yml DeanConversionTool README.md README_EN.md
```

Confirm:

- No credentials or generated test media are present.
- No sentiment-analysis code or documentation was added.
- Existing local-file and batch behavior was not changed.
- Existing online transcription still works with music mode off.

- [ ] **Step 6: Commit**

```bash
git add README.md README_EN.md
git commit -m "docs: document background music recognition"
```
