import SwiftUI

struct MusicScanModePicker: View {
    @Binding var mode: MusicScanMode

    var body: some View {
        Picker("背景音乐", selection: $mode) {
            ForEach(MusicScanMode.allCases, id: \.rawValue) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

struct MusicTrackRow: View {
    let track: RecognizedTrack

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(track.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(2)

            if let artist = track.artist {
                Text(artist)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                if let timeRange {
                    MusicTrackBadge(text: timeRange)
                }
                MusicTrackBadge(text: track.source.displayName)
                if let confidence = track.confidence {
                    MusicTrackBadge(text: "\(Int(confidence.rounded()))%")
                }
            }
        }
        .padding(.vertical, 5)
    }

    private var timeRange: String? {
        guard let startTime = track.startTime, let endTime = track.endTime else {
            return nil
        }
        return "\(formatTime(startTime))-\(formatTime(endTime))"
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct MusicTrackBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(AppTheme.textTertiary)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(AppTheme.surface)
            .cornerRadius(AppTheme.cornerRadiusSmall)
    }
}
