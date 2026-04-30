# Dean Conversion Tool

[中文文档](README.md)

Audio/Video to Transcript Converter for macOS

## Features

- **Whisper Transcription**: Local AI-powered transcription using whisper.cpp with Metal GPU acceleration
- **Speaker Diarization**: Identify and distinguish different speakers using pyannote.audio
- **Emotion Analysis**: Detect sentiment and emotion in speech using Apple's NaturalLanguage framework
- **Multiple Export Formats**: SRT, TXT, Markdown, HTML, JSON
- **Drag & Drop**: Import audio/video files by dragging them into the app
- **Beautiful UI**: Native SwiftUI interface with real-time progress updates

## System Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1/M2/M3) recommended for optimal performance
- 16GB RAM recommended (for large-v3 model)
- Python 3.13+ (for speaker diarization)

## Installation

### 1. Install Dependencies

```bash
# Install whisper.cpp
brew install whisper-cpp

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

This will download the large-v3 model (~3.1GB) to `~/Library/Application Support/DeanConversion/models/`

### 3. Build the App

```bash
# Generate Xcode project
xcodegen generate

# Open in Xcode
open DeanConversionTool.xcodeproj
```

Then build and run from Xcode (⌘R).

## Usage

1. **Launch the app**
2. **Import audio/video file**: 
   - Click "Import Audio/Video" in the sidebar
   - Or drag & drop a file onto the app window
3. **Wait for processing**:
   - Audio preprocessing (converting to WAV format)
   - Whisper transcription
   - Speaker diarization (if enabled)
   - Sentiment analysis
4. **View results**:
   - Browse transcript segments
   - See speaker labels and timestamps
   - View emotion indicators
5. **Export**:
   - Click the Export button
   - Choose your preferred format (SRT, TXT, Markdown, HTML, JSON)

## Supported Formats

### Input Formats
- **Audio**: MP3, WAV, M4A, AAC, FLAC, OGG, WMA
- **Video**: MP4, MOV, AVI, MKV, WebM, M4V

### Output Formats
- **SRT**: SubRip subtitle format for video editing
- **TXT**: Plain text with speaker labels
- **Markdown**: Rich text with formatting, timestamps, and emotion analysis
- **HTML**: Beautiful web page with styling and interactive elements
- **JSON**: Structured data for programmatic access

## Architecture

```
DeanConversionTool/
├── Models/
│   └── TranscriptSegment.swift      # Data models
├── Services/
│   ├── WhisperService.swift         # whisper.cpp integration
│   ├── SentimentAnalysisService.swift  # Apple NaturalLanguage
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

## License

Copyright © 2026 Dean. All rights reserved.

## Acknowledgments

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) - C++ implementation of Whisper
- [pyannote.audio](https://github.com/pyannote/pyannote-audio) - Speaker diarization toolkit
- [FFmpeg](https://ffmpeg.org/) - Audio/video processing
- [Apple NaturalLanguage](https://developer.apple.com/documentation/naturallanguage) - Sentiment analysis
