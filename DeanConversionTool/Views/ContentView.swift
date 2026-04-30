import SwiftUI
import UniformTypeIdentifiers

/// Main content view with NavigationSplitView layout
struct ContentView: View {
    @StateObject private var viewModel = TranscriptViewModel()
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @State private var isDragOver = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar
            SidebarView(viewModel: viewModel)
        } detail: {
            // Main content area
            DetailView(viewModel: viewModel)
        }
        .navigationTitle("Dean Conversion Tool")
        .frame(minWidth: 800, minHeight: 600)
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
        .overlay {
            if isDragOver {
                DropOverlayView()
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, error in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

            let supportedExtensions = ["mp3", "wav", "m4a", "aac", "flac", "ogg", "wma",
                                      "mp4", "mov", "avi", "mkv", "webm", "m4v"]

            if supportedExtensions.contains(url.pathExtension.lowercased()) {
                DispatchQueue.main.async {
                    viewModel.processFile(url: url)
                }
            }
        }

        return true
    }
}

/// Sidebar view with file list and controls
struct SidebarView: View {
    @ObservedObject var viewModel: TranscriptViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header with status
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text("Audio Files")
                        .font(.headline)
                    Spacer()
                }

                // System status
                HStack {
                    StatusIndicator(
                        label: "Whisper",
                        isAvailable: viewModel.isModelLoaded
                    )
                    StatusIndicator(
                        label: "Python",
                        isAvailable: viewModel.isPythonAvailable
                    )
                    StatusIndicator(
                        label: "FFmpeg",
                        isAvailable: viewModel.isFFmpegAvailable
                    )
                }
                .font(.caption)
            }
            .padding()

            Divider()

            // File operations
            VStack(spacing: 12) {
                // Import button
                Button(action: importFile) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Import Audio/Video")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)

                // Quick actions
                if viewModel.transcript != nil {
                    Divider()

                    HStack(spacing: 12) {
                        Button(action: { viewModel.selectAllSegments() }) {
                            Label("Select All", systemImage: "checkmark.circle")
                        }
                        .help("Select all segments")

                        Button(action: { viewModel.deselectAllSegments() }) {
                            Label("Deselect All", systemImage: "circle")
                        }
                        .help("Deselect all segments")

                        Spacer()
                    }
                    .font(.caption)

                    // Copy selected
                    if !viewModel.selectedSegments.isEmpty {
                        Button(action: { viewModel.copySelectedSegments() }) {
                            Label("Copy Selected (\(viewModel.selectedSegments.count))",
                                  systemImage: "doc.on.doc")
                        }
                        .help("Copy selected segments to clipboard")
                    }
                }

                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 200)
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.title = "Import Audio or Video File"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .audio, .movie,
            UTType(filenameExtension: "mp3")!,
            UTType(filenameExtension: "wav")!,
            UTType(filenameExtension: "m4a")!,
            UTType(filenameExtension: "flac")!,
            UTType(filenameExtension: "mp4")!,
            UTType(filenameExtension: "mov")!,
            UTType(filenameExtension: "mkv")!
        ]

        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            viewModel.processFile(url: url)
        }
    }
}

/// Status indicator for system components
struct StatusIndicator: View {
    let label: String
    let isAvailable: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isAvailable ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }
}

/// Main detail view with transcript display
struct DetailView: View {
    @ObservedObject var viewModel: TranscriptViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Loading indicator
            if viewModel.isLoading {
                LoadingView(message: viewModel.loadingMessage, progress: viewModel.progress)
            }

            // Error display
            if let error = viewModel.error {
                ErrorBanner(message: error) {
                    viewModel.error = nil
                }
            }

            // Main content
            if let transcript = viewModel.transcript {
                TranscriptView(viewModel: viewModel, transcript: transcript)
            } else if !viewModel.isLoading {
                WelcomeView()
            }
        }
    }
}

/// Welcome view when no transcript is loaded
struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text("Dean Conversion Tool")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Audio/Video to Transcript Converter")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("Drag & drop an audio or video file to get started")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(icon: "text.bubble", title: "Transcription", description: "Powered by Whisper AI")
                FeatureRow(icon: "person.2", title: "Speaker Diarization", description: "Identify different speakers")
                FeatureRow(icon: "face.smiling", title: "Emotion Analysis", description: "Detect sentiment in speech")
                FeatureRow(icon: "square.and.arrow.up", title: "Export", description: "SRT, TXT, Markdown, HTML, JSON")
            }
            .padding(.top, 20)
        }
        .padding()
    }
}

/// Feature row for welcome view
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.blue)
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

/// Loading view with progress
struct LoadingView: View {
    let message: String
    let progress: Double

    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)

            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text(message)
                    .font(.callout)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

/// Error banner
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.callout)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.orange.opacity(0.2))
    }
}

/// Drop overlay when dragging files
struct DropOverlayView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
            VStack {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
                Text("Drop to Import")
                    .font(.title2)
                    .foregroundColor(.white)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.blue.opacity(0.8))
            )
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
