import XCTest
@testable import DeanConversionTool

@MainActor
final class MusicRecognitionSettingsViewModelTests: XCTestCase {
    func testBlankFieldDoesNotSave() {
        let store = MemoryCredentialStore()
        let model = MusicRecognitionSettingsViewModel(store: store)
        model.appID = "app"
        model.apiKey = " "
        model.apiSecret = "secret"

        model.save()

        XCTAssertEqual(store.saveCount, 0)
        XCTAssertTrue(model.statusIsError)
    }

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
        XCTAssertEqual(model.appID, "")
        XCTAssertEqual(model.apiKey, "")
        XCTAssertEqual(model.apiSecret, "")
    }

    func testLoadingCredentialsDoesNotRevealStoredValues() {
        let store = MemoryCredentialStore()
        store.credentials = XFYunCredentials(
            appID: "stored-app",
            apiKey: "stored-key",
            apiSecret: "stored-secret"
        )

        let model = MusicRecognitionSettingsViewModel(store: store)

        XCTAssertTrue(model.isConfigured)
        XCTAssertEqual(model.appID, "")
        XCTAssertEqual(model.apiKey, "")
        XCTAssertEqual(model.apiSecret, "")
    }

    func testClearRemovesCredentials() {
        let store = MemoryCredentialStore()
        store.credentials = XFYunCredentials(
            appID: "app",
            apiKey: "key",
            apiSecret: "secret"
        )
        let model = MusicRecognitionSettingsViewModel(store: store)

        model.clear()

        XCTAssertNil(store.credentials)
        XCTAssertFalse(model.isConfigured)
        XCTAssertFalse(model.statusIsError)
    }
}

private final class MemoryCredentialStore: XFYunCredentialStoring {
    var credentials: XFYunCredentials?
    var saveCount = 0

    func load() throws -> XFYunCredentials? {
        credentials
    }

    func save(_ credentials: XFYunCredentials) throws {
        self.credentials = credentials
        saveCount += 1
    }

    func clear() throws {
        credentials = nil
    }
}
