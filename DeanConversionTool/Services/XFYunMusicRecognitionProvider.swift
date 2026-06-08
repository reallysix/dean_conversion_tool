import Foundation

final class XFYunMusicRecognitionProvider: MusicRecognitionProvider {
    let name = "讯飞 ACRCloud"

    private let endpoint = URL(
        string: "https://cn-east-1.api.xf-yun.com/v1/private/s29ebee0d"
    )!
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

    func recognize(sample: MusicAudioSample) async throws -> [MusicMatch] {
        guard credentials.isComplete else {
            throw XFYunMusicRecognitionError.incompleteCredentials
        }

        let request = try makeRequest(sample: sample)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw XFYunMusicRecognitionError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw XFYunMusicRecognitionError.httpStatus(httpResponse.statusCode)
        }
        return try parseResponse(data)
    }

    func makeRequest(
        sample: MusicAudioSample,
        date: Date = Date()
    ) throws -> URLRequest {
        let audio = try Data(contentsOf: sample.audioURL).base64EncodedString()
        guard audio.utf8.count <= 1_048_576 else {
            throw XFYunMusicRecognitionError.sampleTooLarge
        }

        let signedURL = try signer.signedURL(
            baseURL: endpoint,
            apiKey: credentials.apiKey,
            apiSecret: credentials.apiSecret,
            date: date
        )
        let body = RequestBody(
            header: Header(appID: credentials.appID, status: 3),
            parameter: Parameter(
                acrMusic: ACRMusic(
                    mode: "music",
                    outputText: OutputTextOptions(
                        encoding: "utf8",
                        compress: "raw",
                        format: "json"
                    )
                )
            ),
            payload: Payload(
                data: AudioPayload(
                    encoding: "lame",
                    sampleRate: 16_000,
                    channels: 1,
                    bitDepth: 16,
                    status: 3,
                    audio: audio,
                    frameSize: 0
                )
            )
        )

        var request = URLRequest(url: signedURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    func parseResponse(_ data: Data) throws -> [MusicMatch] {
        let response = try JSONDecoder().decode(ServiceResponse.self, from: data)
        guard response.header.code == 0 else {
            throw XFYunMusicRecognitionError.service(
                code: response.header.code,
                message: response.header.message
            )
        }
        guard let encodedText = response.payload?.outputText?.text else {
            return []
        }
        guard let resultData = Data(base64Encoded: encodedText) else {
            throw XFYunMusicRecognitionError.invalidResponse
        }

        let result = try JSONDecoder().decode(RecognitionResult.self, from: resultData)
        guard result.status.code == 0 else {
            throw XFYunMusicRecognitionError.recognition(
                code: result.status.code,
                message: result.status.message
            )
        }

        return (result.metadata?.music ?? []).compactMap { music in
            guard let id = music.acrid, let title = music.title else {
                return nil
            }
            let artist = music.artists?
                .compactMap(\.name)
                .filter { !$0.isEmpty }
                .joined(separator: "、")

            return MusicMatch(
                providerRecordingID: id,
                title: title,
                artist: artist?.isEmpty == false ? artist : nil,
                album: music.album?.name,
                confidence: music.score,
                playOffset: music.playOffsetMilliseconds.map { $0 / 1_000 }
            )
        }
    }
}

private extension XFYunMusicRecognitionProvider {
    struct RequestBody: Encodable {
        let header: Header
        let parameter: Parameter
        let payload: Payload
    }

    struct Header: Encodable {
        let appID: String
        let status: Int

        enum CodingKeys: String, CodingKey {
            case appID = "app_id"
            case status
        }
    }

    struct Parameter: Encodable {
        let acrMusic: ACRMusic

        enum CodingKeys: String, CodingKey {
            case acrMusic = "acr_music"
        }
    }

    struct ACRMusic: Encodable {
        let mode: String
        let outputText: OutputTextOptions

        enum CodingKeys: String, CodingKey {
            case mode
            case outputText = "output_text"
        }
    }

    struct OutputTextOptions: Encodable {
        let encoding: String
        let compress: String
        let format: String
    }

    struct Payload: Encodable {
        let data: AudioPayload
    }

    struct AudioPayload: Encodable {
        let encoding: String
        let sampleRate: Int
        let channels: Int
        let bitDepth: Int
        let status: Int
        let audio: String
        let frameSize: Int

        enum CodingKeys: String, CodingKey {
            case encoding
            case sampleRate = "sample_rate"
            case channels
            case bitDepth = "bit_depth"
            case status
            case audio
            case frameSize = "frame_size"
        }
    }

    struct ServiceResponse: Decodable {
        let header: ServiceHeader
        let payload: ServicePayload?
    }

    struct ServiceHeader: Decodable {
        let code: Int
        let message: String?
    }

    struct ServicePayload: Decodable {
        let outputText: ServiceOutputText?

        enum CodingKeys: String, CodingKey {
            case outputText = "output_text"
        }
    }

    struct ServiceOutputText: Decodable {
        let text: String
    }

    struct RecognitionResult: Decodable {
        let status: RecognitionStatus
        let metadata: RecognitionMetadata?
    }

    struct RecognitionStatus: Decodable {
        let code: Int
        let message: String?

        enum CodingKeys: String, CodingKey {
            case code
            case message = "msg"
        }
    }

    struct RecognitionMetadata: Decodable {
        let music: [RecognitionMusic]?
    }

    struct RecognitionMusic: Decodable {
        let acrid: String?
        let title: String?
        let artists: [RecognitionArtist]?
        let album: RecognitionAlbum?
        let playOffsetMilliseconds: Double?
        let score: Double?

        enum CodingKeys: String, CodingKey {
            case acrid
            case title
            case artists
            case album
            case playOffsetMilliseconds = "play_offset_ms"
            case score
        }
    }

    struct RecognitionArtist: Decodable {
        let name: String?
    }

    struct RecognitionAlbum: Decodable {
        let name: String?
    }
}

enum XFYunMusicRecognitionError: LocalizedError {
    case incompleteCredentials
    case sampleTooLarge
    case invalidResponse
    case httpStatus(Int)
    case service(code: Int, message: String?)
    case recognition(code: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .incompleteCredentials:
            return "请先在设置中填写完整的讯飞音乐识别凭据"
        case .sampleTooLarge:
            return "音乐识别音频样本超过 1 MiB 限制"
        case .invalidResponse:
            return "讯飞音乐识别返回了无法解析的数据"
        case .httpStatus(let statusCode):
            return "讯飞音乐识别请求失败（HTTP \(statusCode)）"
        case .service(let code, let message), .recognition(let code, let message):
            let detail = message.flatMap { $0.isEmpty ? nil : "：\($0)" } ?? ""
            return "讯飞音乐识别失败（\(code)）\(detail)"
        }
    }
}
