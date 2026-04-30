# Quick Start Guide

## Step 1: Install Dependencies (Terminal)

```bash
# Install whisper.cpp
brew install whisper-cpp

# Install Python dependencies
pip3 install --break-system-packages pyannote.audio torch torchaudio

# Install xcodegen
brew install xcodegen
```

## Step 2: Download Model

```bash
cd /Users/olivia/MyObjects/2026Projects/dean_conversion_tool
./download_model.sh
```

Wait for the 3.1GB download to complete.

## Step 3: Build the App

```bash
# Generate Xcode project
xcodegen generate

# Open in Xcode
open DeanConversionTool.xcodeproj
```

## Step 4: Run in Xcode

1. Select "DeanConversionTool" scheme
2. Choose "My Mac" as destination
3. Press ⌘R to build and run

## Step 5: Use the App

1. **Import**: Click "Import Audio/Video" or drag & drop a file
2. **Wait**: Processing takes 1-2x the audio duration
3. **Review**: Browse transcript with timestamps and speakers
4. **Export**: Click Export → Choose format (SRT, TXT, Markdown, HTML, JSON)

## Supported Input Formats

- **Audio**: MP3, WAV, M4A, AAC, FLAC, OGG
- **Video**: MP4, MOV, AVI, MKV, WebM

## Tips

- **Best accuracy**: Use the large-v3 model (default)
- **Faster processing**: Change to "medium" or "small" in Settings
- **Speaker detection**: Ensure audio has clear speaker separation
- **Emotion analysis**: Works best with longer sentences

## Troubleshooting

**App won't build?**
- Ensure Xcode is up to date
- Check that whisper.cpp is installed: `which whisper-cli`
- Verify Python packages: `python3 -c "import pyannote.audio"`

**Model not found?**
- Run `./download_model.sh`
- Check: `ls ~/Library/Application\ Support/DeanConversion/models/`

**Slow performance?**
- Close other apps to free up memory
- Use smaller model for faster processing
- Ensure Metal GPU is enabled (check console logs)

**Diarization not working?**
- Check Python: `python3 --version`
- Verify pyannote: `python3 -c "import pyannote.audio; print('OK')"`
- May need to accept pyannote license on first run

## Next Steps

After testing, you can:
- Customize the UI in `Views/ContentView.swift`
- Adjust sentiment thresholds in `Services/SentimentAnalysisService.swift`
- Add new export formats in `Services/ExportService.swift`
- Configure settings in `Views/SettingsView.swift`

Enjoy your new transcription tool! 🎉
