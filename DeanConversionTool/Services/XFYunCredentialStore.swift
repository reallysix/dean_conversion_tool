import Foundation
import Security

extension Notification.Name {
    static let xfyunCredentialsDidChange = Notification.Name(
        "xfyunCredentialsDidChange"
    )
}

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

final class KeychainXFYunCredentialStore: XFYunCredentialStoring {
    private let service = "com.dean.conversiontool.xfyun-acrcloud"
    private let account = "credentials"

    func load() throws -> XFYunCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainCredentialError(status: status)
        }

        return try JSONDecoder().decode(XFYunCredentials.self, from: data)
    }

    func save(_ credentials: XFYunCredentials) throws {
        try clear()

        var query = baseQuery
        query[kSecValueData as String] = try JSONEncoder().encode(credentials)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainCredentialError(status: status)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialError(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

struct KeychainCredentialError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
        return "无法访问钥匙串：\(message)"
    }
}
