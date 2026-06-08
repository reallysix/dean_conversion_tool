import Foundation

protocol MusicRetryAudioDownloading {
    func downloadAudio(
        from urlString: String,
        cookieSource: OnlineVideoCookieSource
    ) async throws -> OnlineVideoDownload

    func cleanup(download: OnlineVideoDownload)
}

final class OnlineVideoMusicRetryDownloader: MusicRetryAudioDownloading {
    func downloadAudio(
        from urlString: String,
        cookieSource: OnlineVideoCookieSource
    ) async throws -> OnlineVideoDownload {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let download = try OnlineVideoService().downloadAudio(
                        from: urlString,
                        cookieSource: cookieSource
                    )
                    continuation.resume(returning: download)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func cleanup(download: OnlineVideoDownload) {
        OnlineVideoService().cleanup(download: download)
    }
}

final class MusicRecognitionRetryService {
    private let credentialStore: XFYunCredentialStoring
    private let downloader: MusicRetryAudioDownloading
    private let sampleProducer: MusicSampleProducing
    private let providerFactory: (XFYunCredentials) -> MusicRecognitionProvider

    init(
        credentialStore: XFYunCredentialStoring = KeychainXFYunCredentialStore(),
        downloader: MusicRetryAudioDownloading = OnlineVideoMusicRetryDownloader(),
        sampleProducer: MusicSampleProducing = MusicSampleService(),
        providerFactory: @escaping (XFYunCredentials) -> MusicRecognitionProvider = {
            XFYunMusicRecognitionProvider(credentials: $0)
        }
    ) {
        self.credentialStore = credentialStore
        self.downloader = downloader
        self.sampleProducer = sampleProducer
        self.providerFactory = providerFactory
    }

    func retry(
        sourceURL: URL,
        transcript: Transcript,
        mode: MusicScanMode,
        cookieSource: OnlineVideoCookieSource,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws -> MusicAnalysis {
        guard let credentials = try credentialStore.load(),
              credentials.isComplete else {
            throw MusicRecognitionRetryError.missingCredentials
        }

        let download = try await downloader.downloadAudio(
            from: sourceURL.absoluteString,
            cookieSource: cookieSource
        )
        defer { downloader.cleanup(download: download) }

        let service = MusicAnalysisService(
            sampleProducer: sampleProducer,
            provider: providerFactory(credentials)
        )
        return await service.analyze(
            sourceURL: download.originalURL,
            audioURL: download.audioURL,
            duration: transcript.duration,
            transcriptSegments: transcript.segments,
            metadata: download.metadata,
            mode: mode,
            onProgress: onProgress
        )
    }
}

enum MusicRecognitionRetryError: LocalizedError, Equatable {
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "尚未配置讯飞识曲凭据"
        }
    }
}
