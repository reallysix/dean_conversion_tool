import Foundation
import Combine

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
            clearInput()
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
            clearInput()
            isConfigured = false
            statusMessage = "讯飞识曲凭证已清除。"
            statusIsError = false
        } catch {
            statusMessage = "清除凭证失败：\(error.localizedDescription)"
            statusIsError = true
        }
    }

    private func clearInput() {
        appID = ""
        apiKey = ""
        apiSecret = ""
    }
}
