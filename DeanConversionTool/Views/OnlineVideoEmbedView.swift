import SwiftUI
import WebKit
import AVFoundation

struct OnlineVideoEmbedView: View {
    let sourceURL: URL
    let seekTime: TimeInterval?
    let seekRequestID: UUID
    let isResolvingDirectPlayback: Bool
    let previewError: String?
    let retryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OnlineVideoPreviewHeader(sourceURL: sourceURL, title: "在线视频预览")

            ZStack {
                OnlineVideoWebView(
                    sourceURL: sourceURL,
                    youtubeVideoID: youtubeVideoID(for: sourceURL),
                    seekTime: seekTime,
                    seekRequestID: seekRequestID
                )

                if isResolvingDirectPlayback {
                    OnlineVideoPreviewStatus(
                        icon: "hourglass",
                        title: "正在准备内嵌播放器",
                        message: "正在通过 yt-dlp 解析临时播放地址。"
                    )
                } else if let previewError {
                    OnlineVideoPreviewStatus(
                        icon: "exclamationmark.triangle",
                        title: "在线播放暂不可用",
                        message: previewError,
                        retryAction: retryAction,
                        openAction: { NSWorkspace.shared.open(sourceURL) }
                    )
                }
            }
                .frame(height: 260)
                .background(Color.black)
                .cornerRadius(AppTheme.cornerRadiusMedium)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                        .stroke(AppTheme.border)
                )
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(AppTheme.workspace)
    }

    private func youtubeVideoID(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }

        if host.contains("youtu.be") {
            return url.pathComponents.dropFirst().first
        }

        if host.contains("youtube.com") {
            if url.path == "/watch" {
                return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "v" })?
                    .value
            }

            if url.path.hasPrefix("/shorts/") || url.path.hasPrefix("/live/") {
                return url.pathComponents.dropFirst().dropFirst().first
            }
        }

        return nil
    }
}

struct OnlineVideoPlayerPreview: View {
    let sourceURL: URL
    let player: AVPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OnlineVideoPreviewHeader(sourceURL: sourceURL, title: "在线视频播放")

            CompactVideoPlayerView(player: player)
                .frame(height: 260)
                .cornerRadius(AppTheme.cornerRadiusMedium)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusMedium)
                        .stroke(AppTheme.border)
                )
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(AppTheme.workspace)
    }
}

struct OnlineVideoPreviewHeader: View {
    let sourceURL: URL
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
                .frame(width: 28, height: 28)
                .background(AppTheme.accentWarm.opacity(0.55))
                .cornerRadius(AppTheme.cornerRadiusSmall)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Text(sourceURL.absoluteString)
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: { NSWorkspace.shared.open(sourceURL) }) {
                Image(systemName: "safari")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("在浏览器中打开")
        }
    }
}

struct OnlineVideoPreviewStatus: View {
    let icon: String
    let title: String
    let message: String
    var retryAction: (() -> Void)?
    var openAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(AppTheme.accentWarm)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 420)

            HStack(spacing: 12) {
                if let retryAction {
                    Button("重试播放", action: retryAction)
                        .font(.system(size: 11, weight: .semibold))
                }
                if let openAction {
                    Button("浏览器打开", action: openAction)
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(AppTheme.accentWarm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Color.black.opacity(0.82))
    }
}

struct OnlineVideoWebView: NSViewRepresentable {
    let sourceURL: URL
    let youtubeVideoID: String?
    let seekTime: TimeInterval?
    let seekRequestID: UUID

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        loadContent(in: webView)
        context.coordinator.loadedSourceURL = sourceURL
        context.coordinator.loadedVideoID = youtubeVideoID
        context.coordinator.handledSeekRequestID = seekRequestID
        return webView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedSourceURL != sourceURL ||
            context.coordinator.loadedVideoID != youtubeVideoID {
            loadContent(in: webView)
            context.coordinator.loadedSourceURL = sourceURL
            context.coordinator.loadedVideoID = youtubeVideoID
        }

        guard context.coordinator.handledSeekRequestID != seekRequestID,
              let seekTime else { return }

        context.coordinator.handledSeekRequestID = seekRequestID
        seek(in: webView, to: seekTime)
    }

    private func loadContent(in webView: WKWebView) {
        if let youtubeVideoID, !youtubeVideoID.isEmpty {
            webView.loadHTMLString(youtubeHTML(videoID: youtubeVideoID), baseURL: URL(string: "https://www.youtube.com"))
        } else {
            webView.load(URLRequest(url: sourceURL))
        }
    }

    private func seek(in webView: WKWebView, to time: TimeInterval) {
        guard youtubeVideoID != nil else { return }
        let seconds = max(0, time)
        webView.evaluateJavaScript("seekToTranscriptTime(\(seconds));") { _, error in
            if let error {
                print("Online video seek failed: \(error.localizedDescription)")
            }
        }
    }

    private func youtubeHTML(videoID: String) -> String {
        let escapedVideoID = videoID
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let embedURL = "https://www.youtube.com/embed/\(escapedVideoID)?enablejsapi=1&playsinline=1&rel=0&modestbranding=1&origin=https%3A%2F%2Fwww.youtube.com"

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body, #player { width: 100%; height: 100%; margin: 0; background: #000; overflow: hidden; }
            iframe { width: 100%; height: 100%; border: 0; display: block; }
          </style>
        </head>
        <body>
          <iframe
            id="player"
            src="\(embedURL)"
            title="YouTube video player"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
            allowfullscreen>
          </iframe>
          <script>
            var pendingSeek = null;
            var player = document.getElementById('player');

            player.addEventListener('load', function() {
              if (pendingSeek !== null) {
                seekToTranscriptTime(pendingSeek);
                pendingSeek = null;
              }
            });

            function seekToTranscriptTime(seconds) {
              if (!player || !player.contentWindow) {
                pendingSeek = seconds;
                return;
              }
              player.contentWindow.postMessage(JSON.stringify({
                event: 'command',
                func: 'seekTo',
                args: [seconds, true]
              }), 'https://www.youtube.com');
            }
          </script>
        </body>
        </html>
        """
    }

    final class Coordinator {
        var loadedSourceURL: URL?
        var loadedVideoID: String?
        var handledSeekRequestID: UUID?
    }
}
