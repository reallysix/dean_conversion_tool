# AGENTS.md

Project guidance for Dean Conversion Tool.

## Project Overview

Dean Conversion Tool is a native macOS SwiftUI app for converting audio/video files into transcripts.

Core stack:
- SwiftUI app targeting macOS 14.0+
- XcodeGen project configuration in `project.yml`
- `whisper-cli` from `whisper-cpp` for local transcription
- FFmpeg for audio/video preprocessing
- Optional Python helper for speaker diarization via `pyannote.audio`

Emotion/sentiment analysis has been removed from the product scope. Do not add new sentiment analysis UI, services, export fields, or documentation unless explicitly requested.

## Build And Verification

Use these commands from the repository root:

```bash
xcodegen generate
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -configuration Debug build
```

For pipeline-level checks, use:

```bash
./test_pipeline.sh
```

The pipeline test depends on local tools and models:
- `/opt/homebrew/bin/whisper-cli`
- `/opt/homebrew/bin/ffmpeg`
- `~/Library/Application Support/DeanConversion/models/ggml-large-v3.bin`
- Python 3 with `pyannote.audio` for speaker diarization checks

## Development Rules

- Keep changes surgical and tied directly to the requested task.
- Preserve existing uncommitted work unless the user explicitly asks to remove it.
- Match the current SwiftUI style and project organization.
- Update `project.yml` when adding or removing source/resource paths that XcodeGen needs to know about.
- Regenerate the Xcode project after structural changes.
- Prefer compile verification with `xcodebuild` before considering work complete.

## Architecture Notes

Important files:
- `DeanConversionTool/ViewModels/TranscriptViewModel.swift`: coordinates import, preprocessing, transcription, diarization, export, and batch flow.
- `DeanConversionTool/Services/WhisperService.swift`: invokes `whisper-cli`.
- `DeanConversionTool/Services/AudioPreprocessingService.swift`: invokes FFmpeg.
- `DeanConversionTool/Services/SpeakerDiarizationService.swift`: invokes the Python diarization helper.
- `DeanConversionTool/Services/ExportService.swift`: writes SRT, TXT, Markdown, HTML, and JSON exports.
- `PythonHelpers/speaker_diarization.py`: pyannote-based speaker diarization script bundled as a resource.

## Product Scope Notes

Current known follow-up areas:
- Stabilize the existing UI refresh and batch-processing work.
- Replace waveform placeholders with real waveform data if requested.
- Add transcript editing only if explicitly requested.
- Keep speaker diarization optional and resilient when Python dependencies or HuggingFace access are missing.
