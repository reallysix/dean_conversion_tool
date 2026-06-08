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
    private let notificationCenter: NotificationCenter

    init(
        store: XFYunCredentialStoring = KeychainXFYunCredentialStore(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.store = store
        self.notificationCenter = notificationCenter
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
        let trimmedAppID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPISecret = apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)

        if isConfigured &&
            trimmedAppID.isEmpty &&
            trimmedAPIKey.isEmpty &&
            trimmedAPISecret.isEmpty {
            statusMessage = "讯飞识曲凭据已配置，无需重复保存。如需更新，请完整填写三项。"
            statusIsError = false
            return
        }

        let credentials = XFYunCredentials(
            appID: trimmedAppID,
            apiKey: trimmedAPIKey,
            apiSecret: trimmedAPISecret
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
            notificationCenter.post(name: .xfyunCredentialsDidChange, object: nil)
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
            notificationCenter.post(name: .xfyunCredentialsDidChange, object: nil)
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
