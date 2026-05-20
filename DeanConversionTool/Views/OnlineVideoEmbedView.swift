import SwiftUI
import WebKit

struct OnlineVideoEmbedView: View {
    let sourceURL: URL

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

            OnlineVideoWebView(url: embedURL(for: sourceURL) ?? sourceURL)
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

    private func embedURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }

        if host.contains("youtu.be") {
            let videoID = url.pathComponents.dropFirst().first
            return youtubeEmbedURL(videoID: videoID)
        }

        if host.contains("youtube.com") {
            if url.path == "/watch" {
                let videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "v" })?
                    .value
                return youtubeEmbedURL(videoID: videoID)
            }

            if url.path.hasPrefix("/shorts/") || url.path.hasPrefix("/live/") {
                let videoID = url.pathComponents.dropFirst().dropFirst().first
                return youtubeEmbedURL(videoID: videoID)
            }
        }

        return nil
    }

    private func youtubeEmbedURL(videoID: String?) -> URL? {
        guard let videoID, !videoID.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/embed/\(videoID)"
        components.queryItems = [
            URLQueryItem(name: "playsinline", value: "1"),
            URLQueryItem(name: "rel", value: "0")
        ]
        return components.url
    }
}

struct OnlineVideoWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }
}
