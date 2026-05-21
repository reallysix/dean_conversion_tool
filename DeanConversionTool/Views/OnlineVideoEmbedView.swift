import SwiftUI
import WebKit

struct OnlineVideoEmbedView: View {
    let sourceURL: URL
    let seekTime: TimeInterval?
    let seekRequestID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.accentWarm.opacity(0.55))
                    .cornerRadius(AppTheme.cornerRadiusSmall)

                VStack(alignment: .leading, spacing: 2) {
                    Text("在线视频预览")
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

            OnlineVideoWebView(
                sourceURL: sourceURL,
                youtubeVideoID: youtubeVideoID(for: sourceURL),
                seekTime: seekTime,
                seekRequestID: seekRequestID
            )
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

struct OnlineVideoWebView: NSViewRepresentable {
    let sourceURL: URL
    let youtubeVideoID: String?
    let seekTime: TimeInterval?
    let seekRequestID: UUID

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

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
        webView.evaluateJavaScript("seekToTranscriptTime(\(seconds));")
    }

    private func youtubeHTML(videoID: String) -> String {
        let escapedVideoID = videoID
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body, #player { width: 100%; height: 100%; margin: 0; background: #000; overflow: hidden; }
          </style>
        </head>
        <body>
          <div id="player"></div>
          <script src="https://www.youtube.com/iframe_api"></script>
          <script>
            var player;
            var pendingSeek = null;
            function onYouTubeIframeAPIReady() {
              player = new YT.Player('player', {
                width: '100%',
                height: '100%',
                videoId: '\(escapedVideoID)',
                playerVars: { playsinline: 1, rel: 0 },
                events: {
                  onReady: function() {
                    if (pendingSeek !== null) {
                      player.seekTo(pendingSeek, true);
                      pendingSeek = null;
                    }
                  }
                }
              });
            }
            function seekToTranscriptTime(seconds) {
              if (player && typeof player.seekTo === 'function') {
                player.seekTo(seconds, true);
              } else {
                pendingSeek = seconds;
              }
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
