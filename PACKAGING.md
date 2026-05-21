# Packaging

This project supports a local unsigned macOS package flow, plus an opt-in Developer ID signing and notarization flow when Apple Developer values are provided locally.

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

## Signing Configuration

Unsigned packaging remains the default so local development does not require an Apple Developer account.

For signed release builds, copy the example config and fill in real Apple Developer values:

```bash
cp Scripts/release_config.example.env Scripts/release_config.env
open Scripts/release_config.env
```

`Scripts/release_config.env` is ignored by Git. It can define:

- `APP_BUNDLE_ID`: the registered reverse-DNS bundle identifier.
- `APPLE_TEAM_ID`: the Apple Developer Team ID.
- `DEVELOPER_ID_APPLICATION`: the exact Developer ID Application certificate name from Keychain Access.
- `NOTARYTOOL_PROFILE`: the keychain profile created with `xcrun notarytool store-credentials`.

With signing values present, the package script enables manual Developer ID signing and hardened runtime:

```bash
Scripts/package_app.sh
```

To submit the generated DMG for notarization and staple the result:

```bash
Scripts/package_app.sh --notarize
```

## Output Paths

- App bundle: `build/package/Release/staging/Dean Conversion Tool.app`
- DMG: `build/package/Release/Dean Conversion Tool.dmg`
- Derived data: `build/package/DerivedData`

## Current Limitations

- The package is unsigned unless `Scripts/release_config.env` provides Developer ID signing values.
- Notarization requires a local `notarytool` profile and must be requested with `--notarize`.
- The app still depends on local command-line tools such as `whisper-cli`, `ffmpeg`, `ffprobe`, `yt-dlp`, and `deno`.
- The Whisper model is not bundled. The app should download or locate it at runtime.

## Dependency Install Policy

The app should not silently run Homebrew installs on launch. The first distributable version should detect missing tools in the right-side environment panel and let the user copy explicit install commands. `Scripts/check_dependencies.sh --install` remains the user-initiated path for installing all command-line dependencies.

## Model Distribution Policy

The first distributable version should not bundle Whisper models inside the `.dmg`. Even a small bundled model would make the installer larger while still leaving accuracy tradeoffs for users to understand. The default release strategy is to ship a small app package and download `Whisper large-v3` at runtime into:

```text
~/Library/Application Support/DeanConversion/models/
```

Future releases can add a model picker and optional small-model downloads, but the current app path remains fixed to `ggml-large-v3.bin`.

## Release Checklist

- [ ] Run `Scripts/package_app.sh`.
- [ ] Open the app from `build/package/Release/staging`.
- [ ] For signed releases, run `codesign --verify --deep --strict --verbose=2 "build/package/Release/staging/Dean Conversion Tool.app"`.
- [ ] For notarized releases, run `spctl --assess --type open --verbose "build/package/Release/Dean Conversion Tool.dmg"`.
- [ ] Confirm the right-side environment status detects dependencies correctly.
- [ ] Confirm local file transcription still starts.
- [ ] Confirm online URL transcription reports clear dependency errors when tools are missing.
- [ ] Confirm model missing/download states are understandable.
