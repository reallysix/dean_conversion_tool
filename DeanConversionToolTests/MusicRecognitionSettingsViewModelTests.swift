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

    func testSavePostsCredentialStatusChangeNotification() {
        let store = MemoryCredentialStore()
        let notificationCenter = NotificationCenter()
        let notificationExpectation = expectation(
            description: "凭据状态变化通知"
        )
        let token = notificationCenter.addObserver(
            forName: .xfyunCredentialsDidChange,
            object: nil,
            queue: nil
        ) { _ in
            notificationExpectation.fulfill()
        }
        defer { notificationCenter.removeObserver(token) }
        let model = MusicRecognitionSettingsViewModel(
            store: store,
            notificationCenter: notificationCenter
        )
        model.appID = "app"
        model.apiKey = "key"
        model.apiSecret = "secret"

        model.save()

        wait(for: [notificationExpectation], timeout: 1)
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

    func testSavingBlankFieldsWhenAlreadyConfiguredDoesNotReportError() {
        let store = MemoryCredentialStore()
        store.credentials = XFYunCredentials(
            appID: "stored-app",
            apiKey: "stored-key",
            apiSecret: "stored-secret"
        )
        let model = MusicRecognitionSettingsViewModel(store: store)

        model.save()

        XCTAssertEqual(store.saveCount, 0)
        XCTAssertFalse(model.statusIsError)
        XCTAssertEqual(
            model.statusMessage,
            "讯飞识曲凭据已配置，无需重复保存。如需更新，请完整填写三项。"
        )
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
