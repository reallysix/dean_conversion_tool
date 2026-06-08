import CryptoKit
import Foundation

struct XFYunRequestSigner {
    func signedURL(
        baseURL: URL,
        apiKey: String,
        apiSecret: String,
        date: Date = Date()
    ) throws -> URL {
        guard let host = baseURL.host else {
            throw XFYunSigningError.invalidURL
        }

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
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(signatureOrigin.utf8),
            using: key
        )
        let authorizationOrigin = """
        api_key="\(apiKey)", algorithm="hmac-sha256", headers="host date request-line", signature="\(Data(signature).base64EncodedString())"
        """

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(
                name: "authorization",
                value: Data(authorizationOrigin.utf8).base64EncodedString()
            ),
            URLQueryItem(name: "date", value: dateString),
            URLQueryItem(name: "host", value: host),
        ]
        guard let signedURL = components?.url else {
            throw XFYunSigningError.invalidURL
        }
        return signedURL
    }
}

enum XFYunSigningError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        "讯飞音乐识别地址无效"
    }
}
