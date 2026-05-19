import SwiftUI
import AVKit
import AVFoundation

/// Custom NSView using AVPlayerLayer directly to avoid VisionKit/Metal crash
class PlayerNSView: NSView {
    private let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPlayer(_ player: AVPlayer) {
        playerLayer.player = player
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

/// Video player view using custom PlayerNSView
struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.setPlayer(player)
        return view
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {
        nsView.setPlayer(player)
    }
}

/// Compact video player for inline display (video only, controls in BottomBar)
struct CompactVideoPlayerView: View {
    let player: AVPlayer

    var body: some View {
        VideoPlayerView(player: player)
            .frame(minHeight: 200, maxHeight: 400)
            .background(Color.black)
    }
}
