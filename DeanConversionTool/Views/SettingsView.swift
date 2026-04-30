import SwiftUI

/// Settings view for configuring the application
struct SettingsView: View {
    @AppStorage("defaultLanguage") private var defaultLanguage = "auto"
    @AppStorage("enableSpeakerDiarization") private var enableSpeakerDiarization = true
    @AppStorage("enableSentimentAnalysis") private var enableSentimentAnalysis = true
    @AppStorage("whisperModelSize") private var whisperModelSize = "large-v3"

    var body: some View {
        TabView {
            GeneralSettingsView(
                defaultLanguage: $defaultLanguage,
                whisperModelSize: $whisperModelSize
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }

            FeatureSettingsView(
                enableSpeakerDiarization: $enableSpeakerDiarization,
                enableSentimentAnalysis: $enableSentimentAnalysis
            )
            .tabItem {
                Label("Features", systemImage: "slider.horizontal.3")
            }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

/// General settings
struct GeneralSettingsView: View {
    @Binding var defaultLanguage: String
    @Binding var whisperModelSize: String

    let languages = [
        ("auto", "Auto-detect"),
        ("zh", "Chinese"),
        ("en", "English"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German")
    ]

    let modelSizes = [
        ("tiny", "Tiny (~75MB)"),
        ("base", "Base (~142MB)"),
        ("small", "Small (~466MB)"),
        ("medium", "Medium (~1.5GB)"),
        ("large-v3", "Large V3 (~3.1GB)")
    ]

    var body: some View {
        Form {
            Section("Transcription") {
                Picker("Default Language", selection: $defaultLanguage) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }

                Picker("Whisper Model", selection: $whisperModelSize) {
                    ForEach(modelSizes, id: \.0) { size, name in
                        Text(name).tag(size)
                    }
                }
                .help("Larger models are more accurate but slower")

                Text("Note: Model changes require app restart")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

/// Feature settings
struct FeatureSettingsView: View {
    @Binding var enableSpeakerDiarization: Bool
    @Binding var enableSentimentAnalysis: Bool

    var body: some View {
        Form {
            Section("Features") {
                Toggle("Enable Speaker Diarization", isOn: $enableSpeakerDiarization)
                    .help("Identify different speakers in the audio")

                if enableSpeakerDiarization {
                    Text("Requires Python with pyannote.audio installed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }

                Toggle("Enable Sentiment Analysis", isOn: $enableSentimentAnalysis)
                    .help("Analyze emotion and sentiment in speech")

                if enableSentimentAnalysis {
                    Text("Uses Apple's NaturalLanguage framework")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }
            }

            Section("Export") {
                Toggle("Include timestamps in export", isOn: .constant(true))
                Toggle("Include speaker labels", isOn: .constant(true))
                Toggle("Include sentiment data", isOn: .constant(true))
            }
        }
        .padding()
    }
}

/// About settings
struct AboutSettingsView: View {
    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        Text("Dean Conversion Tool")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Version 1.0.0")
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                Text("Audio/Video to Transcript Converter")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Powered by:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack {
                        Image(systemName: "cpu")
                        Text("Whisper.cpp (Local AI Transcription)")
                    }
                    .font(.caption)

                    HStack {
                        Image(systemName: "person.2")
                        Text("pyannote.audio (Speaker Diarization)")
                    }
                    .font(.caption)

                    HStack {
                        Image(systemName: "face.smiling")
                        Text("Apple NaturalLanguage (Sentiment Analysis)")
                    }
                    .font(.caption)
                }

                Spacer()

                Text("Built with SwiftUI for macOS")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

#Preview {
    SettingsView()
}
