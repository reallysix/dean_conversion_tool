# Background Music Recognition Retry Design

## Goal

Make missing iFlytek credentials and retryable music-recognition failures easy to recover from without rerunning transcription or creating duplicate projects.

## Confirmed Behavior

- Saving iFlytek credentials only saves configuration. It does not automatically start recognition or consume quota.
- The user explicitly starts another attempt with `重新识别`.
- A retry reuses the existing transcript and its time segments.
- A retry does not invoke Whisper or speaker diarization.
- A retry does not create another history project or duplicate transcript outputs.
- The updated music result replaces the current project's existing `music-analysis.json`.

## Result States

The background-music panel distinguishes these states:

1. **Credentials not configured**
   - Message: `尚未配置讯飞识曲凭据`
   - Primary action: `立即设置`
   - Secondary action: `重新识别`
   - `立即设置` opens the existing Settings window directly at the background-music credential section.
   - `重新识别` checks credentials before downloading audio. If credentials are still missing, it keeps the current result and opens the settings path instead of starting work.

2. **Recognition completed with no match**
   - Message: `暂未识别到歌曲`
   - Action: `重新识别`
   - The unmatched sample count is shown only when samples were actually submitted.

3. **Recognition failed**
   - Message contains the actionable provider, download, or sample-extraction error.
   - Action: `重新识别`
   - Successful tracks from a partial run remain visible.

4. **Recognition succeeded**
   - Existing track rows, provider details, unmatched count, and export actions remain.
   - Action: `重新识别` is available for an intentional refresh.

## Retry Data Flow

1. Resolve the current online video's original URL from the loaded transcript/history project.
2. Verify complete iFlytek credentials before any download.
3. Download a temporary audio copy using the existing `yt-dlp` and cookie-source settings.
4. Run `MusicAnalysisService` with the existing transcript duration and segments.
5. Replace the in-memory music result.
6. Atomically overwrite the current project's music-analysis output and update project metadata.
7. Remove the temporary download.

The app continues to store only the source URL, transcript outputs, and music-analysis result. It does not retain copied online audio.

## UI And Progress

- Music retry has its own busy state so the transcript stays visible and usable.
- While retrying, the action shows recognition progress and cannot be started twice.
- General task status must not imply that the transcript is running again.
- Opening Settings does not discard the loaded project or its transcript.

## Persistence

`MusicAnalysis` records a machine-readable outcome so the UI does not infer state from localized warning text. Decoding remains compatible with existing archived music-analysis files.

`HistoryProjectStore` gains an update operation that writes the music result into the existing project directory and updates `project.json`; it never calls the create-project path.

## Verification

- Missing credentials produce the configuration state rather than `未命中样本`.
- Clicking `立即设置` opens Settings at background-music configuration.
- Saving credentials performs no recognition request.
- Retrying calls the music path but not Whisper or diarization.
- Retrying overwrites the same project's result and leaves the project count unchanged.
- Download/provider failures leave the transcript and previous usable tracks intact.
- Existing history files without the new outcome field still load.
- Unit tests and the macOS Debug build pass.
