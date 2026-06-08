import XCTest
@testable import DeanConversionTool

final class XFYunRequestSignerTests: XCTestCase {
    func testCredentialsRequireAllThreeValues() {
        XCTAssertFalse(
            XFYunCredentials(appID: "app", apiKey: "", apiSecret: "secret").isComplete
        )
        XCTAssertTrue(
            XFYunCredentials(appID: "app", apiKey: "key", apiSecret: "secret").isComplete
        )
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
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let values = Dictionary(
            uniqueKeysWithValues: try XCTUnwrap(components.queryItems).map {
                ($0.name, $0.value ?? "")
            }
        )

        XCTAssertEqual(values["host"], "cn-east-1.api.xf-yun.com")
        XCTAssertEqual(values["date"], "Thu, 31 Mar 2022 02:42:08 GMT")
        XCTAssertEqual(
            values["authorization"],
            "YXBpX2tleT0idGVzdC1hcGkta2V5IiwgYWxnb3JpdGhtPSJobWFjLXNoYTI1NiIsIGhlYWRlcnM9Imhvc3QgZGF0ZSByZXF1ZXN0LWxpbmUiLCBzaWduYXR1cmU9IjR2cnd4YVUzdmJLYnMyeWFobHJGd1c0RFlxUGVoWXl3dXFhWW5zODdBbzg9Ig=="
        )
    }
}
