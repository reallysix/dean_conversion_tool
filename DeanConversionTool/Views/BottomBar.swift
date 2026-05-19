import SwiftUI
import AVFoundation

struct BottomBar: View {
    @ObservedObject var viewModel: TranscriptViewModel
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var timeObserver: Any?
    @State private var observedPlayer: AVPlayer?

    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause
            if viewModel.player != nil {
                Button(action: { togglePlayPause() }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(AppTheme.surface)
                        .cornerRadius(AppTheme.cornerRadiusSmall)
                }
                .buttonStyle(.plain)

                // Current time
                Text(formatTime(currentTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(width: 44)

                // Progress slider
                Slider(value: Binding(
                    get: { currentTime },
                    set: { newValue in
                        currentTime = newValue
                        viewModel.player?.seek(to: CMTime(seconds: newValue, preferredTimescale: 600))
                    }
                ), in: 0...max(duration, 1))
                .disabled(duration == 0)
                .tint(AppTheme.accent)

                // Duration
                Text(formatTime(duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(width: 44)
            } else {
                Spacer()
                Text("导入文件后可播放")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textTertiary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.sidebarBackground)
        .onAppear { setupTimeObserver() }
        .onDisappear { removeTimeObserver() }
        .onChange(of: viewModel.player) {
            removeTimeObserver()
            setupTimeObserver()
        }
        .onChange(of: viewModel.transcript?.duration) {
            if let transcriptDuration = viewModel.transcript?.duration, transcriptDuration > 0 {
                duration = transcriptDuration
            }
        }
    }

    private func togglePlayPause() {
        guard let player = viewModel.player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func setupTimeObserver() {
        guard let player = viewModel.player else { return }

        // Use transcript duration as primary source (already computed from file)
        if let transcriptDuration = viewModel.transcript?.duration, transcriptDuration > 0 {
            duration = transcriptDuration
        } else {
            // Fallback to player item duration
            let itemDuration = player.currentItem?.duration
            if let itemDuration = itemDuration, itemDuration.isNumeric {
                duration = itemDuration.seconds
            } else {
                duration = 0
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 10),
            queue: .main
        ) { time in
            currentTime = time.seconds
            isPlaying = player.rate > 0
            // Update duration if it becomes available later
            if duration == 0, let itemDuration = player.currentItem?.duration, itemDuration.isNumeric {
                duration = itemDuration.seconds
            }
        }
        observedPlayer = player
    }

    private func removeTimeObserver() {
        if let observer = timeObserver, let player = observedPlayer {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        observedPlayer = nil
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN && !time.isInfinite else { return "00:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
