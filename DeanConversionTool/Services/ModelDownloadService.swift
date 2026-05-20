import Foundation

final class ModelDownloadService: NSObject, URLSessionDownloadDelegate {
    private let modelURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!
    static let modelName = "Whisper large-v3"
    static let modelFileName = "ggml-large-v3.bin"
    static let modelSizeDescription = "约 3.1GB"

    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var destinationURL: URL?
    private var onProgress: ((Double) -> Void)?
    private var onComplete: ((Result<Void, Error>) -> Void)?
    private var didFinish = false

    var downloadPageURL: URL {
        modelURL
    }

    func downloadModel(to destinationURL: URL, onProgress: @escaping (Double) -> Void, onComplete: @escaping (Result<Void, Error>) -> Void) {
        cancel()

        self.destinationURL = destinationURL
        self.onProgress = onProgress
        self.onComplete = onComplete
        didFinish = false

        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            finish(.failure(error))
            return
        }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 6

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        task = session?.downloadTask(with: modelURL)
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { [onProgress] in
            onProgress?(progress)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destinationURL else {
            finish(.failure(ModelDownloadError.missingDestination))
            return
        }

        do {
            let temporaryURL = destinationURL.appendingPathExtension("download")
            try? FileManager.default.removeItem(at: temporaryURL)
            try FileManager.default.moveItem(at: location, to: temporaryURL)
            let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
            let fileSize = attributes[.size] as? NSNumber
            guard (fileSize?.int64Value ?? 0) > 0 else {
                try? FileManager.default.removeItem(at: temporaryURL)
                finish(.failure(ModelDownloadError.invalidFile))
                return
            }
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, !didFinish else { return }
        finish(.failure(error))
    }

    private func finish(_ result: Result<Void, Error>) {
        didFinish = true
        task = nil
        session?.finishTasksAndInvalidate()
        session = nil

        DispatchQueue.main.async { [onComplete] in
            onComplete?(result)
        }
    }
}

enum ModelDownloadError: LocalizedError {
    case missingDestination
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .missingDestination:
            return "模型下载目标路径不可用"
        case .invalidFile:
            return "模型文件下载不完整，请重试"
        }
    }
}
