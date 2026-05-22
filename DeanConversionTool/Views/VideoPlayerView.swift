import SwiftUI
import AVKit
import AVFoundation
import CoreImage

/// Custom NSView using AVPlayerLayer directly to avoid VisionKit/Metal crash
class PlayerNSView: NSView {
    private let backgroundPlayerLayer = AVPlayerLayer()
    private let foregroundPlayerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor

        backgroundPlayerLayer.videoGravity = .resizeAspectFill
        backgroundPlayerLayer.opacity = 0.42
        if let blurFilter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 22]) {
            backgroundPlayerLayer.filters = [blurFilter]
        }

        foregroundPlayerLayer.videoGravity = .resizeAspect

        layer?.addSublayer(backgroundPlayerLayer)
        layer?.addSublayer(foregroundPlayerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPlayer(_ player: AVPlayer) {
        backgroundPlayerLayer.player = player
        foregroundPlayerLayer.player = player
    }

    override func layout() {
        super.layout()
        backgroundPlayerLayer.frame = bounds.insetBy(dx: -28, dy: -28)
        foregroundPlayerLayer.frame = bounds
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
            .background(Color(hex: 0x111015))
    }
}
