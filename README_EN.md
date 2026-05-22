# Dean Conversion Tool

[中文文档](README.md)

Audio/Video to Transcript Converter for macOS.

## Features

- **Local Whisper transcription**: Transcribe audio and video locally through `whisper-cli` from whisper.cpp.
- **Audio/video import**: Drag common audio and video files into the app or import them from the workstation.
- **Online video transcription**: Paste public links supported by `yt-dlp`, such as YouTube, Bilibili, and Douyin links.
- **Embedded video preview**: Play local videos and resolved online videos inside the app. The player keeps the full foreground frame and fills side bars with a blurred video background.
- **Playback-linked transcript**: Click a timestamp or transcript segment to seek the video. During playback, the current subtitle segment is highlighted and the transcript follows the playhead.
- **History archive**: Store transcript projects under `~/Documents/DeanConversionTool/Projects`, including generated transcript/subtitle files and source metadata without copying full media files.
- **Speaker diarization**: Optionally identify and distinguish speakers using `pyannote.audio`.
- **Multiple export formats**: SRT, TXT, Markdown, HTML, and JSON.
- **Dependency checks**: Inspect Whisper, model, FFmpeg, `yt-dlp`, Deno, and optional diarization status from the app.

## System Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1/M2/M3) recommended for optimal performance
- 16GB RAM recommended (for large-v3 model)
- Homebrew
- Python 3.13+ (for speaker diarization)

## Installation

### 1. Install Dependencies

```bash
# Install whisper.cpp
brew install whisper-cpp

# Install audio/video and online video dependencies
brew install ffmpeg yt-dlp deno

# Install Python dependencies for speaker diarization
pip3 install --break-system-packages pyannote.audio torch torchaudio

# Install xcodegen (for project generation)
brew install xcodegen
```

### 2. Download Whisper Model

```bash
# Run the model download script
./download_model.sh
```

This will download the large-v3 model (~3.1GB) to `~/Library/Application Support/DeanConversion/models/`.

You can also check local command-line dependencies with:

```bash
Scripts/check_dependencies.sh
```

### 3. Build the App

```bash
# Generate Xcode project
xcodegen generate

# Build Debug
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -configuration Debug build
```

You can also open `DeanConversionTool.xcodeproj` in Xcode and run the `DeanConversionTool` scheme.

## Usage

1. **Launch the app**
2. **Import media or paste a public video link**:
   - Click the local import action or drag and drop an audio/video file.
   - Paste a supported online video URL and start transcription.
3. **Wait for processing**:
   - Audio preprocessing (converting to WAV format)
   - Whisper transcription
   - Speaker diarization (if enabled)
4. **View results**:
   - Browse transcript segments.
   - See speaker labels and timestamps.
   - Click a timestamp or text segment to seek the player.
   - Let playback automatically highlight and follow the current subtitle segment.
5. **Export**:
   - Click the Export button
   - Choose your preferred format (SRT, TXT, Markdown, HTML, JSON)

## Supported Formats

### Input Formats
- **Audio**: MP3, WAV, M4A, AAC, FLAC, OGG, WMA
- **Video**: MP4, MOV, AVI, MKV, WebM, M4V
- **Online video**: Public links supported by `yt-dlp`, including YouTube, Bilibili, Douyin, and similar platforms

### Output Formats
- **SRT**: SubRip subtitle format for video editing
- **TXT**: Plain text with speaker labels
- **Markdown**: Rich text with formatting, timestamps, and speaker labels
- **HTML**: Beautiful web page with styling and interactive elements
- **JSON**: Structured data for programmatic access

## Architecture

```
DeanConversionTool/
├── Models/
│   └── TranscriptSegment.swift      # Data models
├── Services/
│   ├── WhisperService.swift         # whisper.cpp integration
│   ├── OnlineVideoService.swift     # yt-dlp online video integration
│   ├── HistoryProjectStore.swift    # Project archive storage
│   ├── ModelDownloadService.swift   # Whisper model download
│   ├── SpeakerDiarizationService.swift # pyannote.audio bridge
│   ├── AudioPreprocessingService.swift # FFmpeg wrapper
│   └── ExportService.swift          # Multi-format export
├── ViewModels/
│   └── TranscriptViewModel.swift    # Main app logic
├── Views/
│   ├── ContentView.swift            # Main layout
│   ├── TranscriptView.swift         # Transcript display
│   └── SettingsView.swift           # App settings
├── Resources/                       # App resources
└── Bridging-Header.h                # whisper.cpp C API bridge
```

## Performance

- **Whisper large-v3**: ~1-2x realtime on M2 Pro with Metal acceleration
- **Speaker diarization**: Adds ~10-20% processing time
- **Memory usage**: ~6-8GB during transcription (with large-v3 model)
- **Disk space**: ~3.1GB for whisper model

## Troubleshooting

### "Model not found" error
Run `./download_model.sh` to download the whisper model.

### "Python not found" error
Ensure Python 3 is installed and pyannote.audio is available:
```bash
python3 -c "import pyannote.audio; print('OK')"
```

### Slow transcription
- Ensure you're on Apple Silicon (M1/M2/M3)
- Check that Metal GPU acceleration is enabled (logged on first run)
- Consider using a smaller model (medium or small) for faster processing

### Memory warnings
The large-v3 model requires ~6-8GB RAM. Close other memory-intensive apps if needed.

## Roadmap

- Word-level timing and live word highlighting.
- More compact task/environment status in low-height windows.
- Transcript row spacing, hover states, history title tooltips, and media workspace hierarchy refinements.

## License

Copyright © 2026 Dean. All rights reserved.

## Acknowledgments

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) - C++ implementation of Whisper
- [pyannote.audio](https://github.com/pyannote/pyannote-audio) - Speaker diarization toolkit
- [FFmpeg](https://ffmpeg.org/) - Audio/video processing
