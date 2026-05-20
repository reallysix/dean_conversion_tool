# Packaging

This project currently supports a local unsigned macOS package flow. Formal code signing and notarization are still tracked in `TODO.md`.

## Package Types

- `.app`: the macOS application bundle produced by Xcode.
- `.dmg`: the first distributable package format for local testing. It contains the `.app` bundle.
- `.pkg`: not used yet. It may be useful later if the app needs an installer-driven dependency step.

For the current stage, prefer `.dmg` because it is simple, easy to inspect, and enough to test app launch behavior outside Xcode.

## Build Commands

Debug build:

```bash
xcodegen generate
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -configuration Debug build
```

Release package:

```bash
Scripts/package_app.sh
```

The package script will:

1. Run `Scripts/check_dependencies.sh`.
2. Regenerate the Xcode project with XcodeGen.
3. Build the `Release` app into `build/package/DerivedData`.
4. Copy the app bundle into `build/package/Release/staging`.
5. Verify required bundled resources such as `speaker_diarization.py`.
6. Create `build/package/Release/Dean Conversion Tool.dmg`.

To build only the `.app` bundle:

```bash
Scripts/package_app.sh --skip-dmg
```

To skip local dependency checks:

```bash
Scripts/package_app.sh --skip-dependency-check
```

## Output Paths

- App bundle: `build/package/Release/staging/Dean Conversion Tool.app`
- DMG: `build/package/Release/Dean Conversion Tool.dmg`
- Derived data: `build/package/DerivedData`

## Current Limitations

- The package is unsigned.
- The package is not notarized.
- The app still depends on local command-line tools such as `whisper-cli`, `ffmpeg`, `ffprobe`, `yt-dlp`, and `deno`.
- The Whisper model is not bundled. The app should download or locate it at runtime.

## Dependency Install Policy

The app should not silently run Homebrew installs on launch. The first distributable version should detect missing tools in the right-side environment panel and let the user copy explicit install commands. `Scripts/check_dependencies.sh --install` remains the user-initiated path for installing all command-line dependencies.

## Release Checklist

- [ ] Run `Scripts/package_app.sh`.
- [ ] Open the app from `build/package/Release/staging`.
- [ ] Confirm the right-side environment status detects dependencies correctly.
- [ ] Confirm local file transcription still starts.
- [ ] Confirm online URL transcription reports clear dependency errors when tools are missing.
- [ ] Confirm model missing/download states are understandable.
