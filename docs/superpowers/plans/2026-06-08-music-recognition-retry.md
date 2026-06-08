# 背景音乐重新识别实施计划

> **供自动化开发使用：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans`，按照复选框逐项执行，并在每个功能步骤中遵循测试驱动开发。

**目标：** 在未配置科大讯飞凭据、未识别到歌曲或识别失败时，提供“立即设置”和“重新识别”，并确保重新识别只执行音频下载、采样和歌曲识别，不重新转写字幕，也不创建重复项目。

**架构：** `MusicAnalysis` 保存机器可读的识别结果状态和已提交样本数量；新的 `MusicRecognitionRetryService` 负责凭据检查、临时音频下载和歌曲识别，且不依赖 Whisper。`TranscriptViewModel` 只协调界面状态，并通过 `HistoryProjectStore` 将结果覆盖写入当前项目。

**技术栈：** Swift 5、SwiftUI、Foundation、Security Keychain、FFmpeg、yt-dlp、XCTest、XcodeGen。

---

## 文件清单

新增：

- `DeanConversionTool/Services/MusicRecognitionRetryService.swift`：只负责背景音乐重新识别，不接触字幕转写。
- `DeanConversionToolTests/MusicRecognitionRetryServiceTests.swift`：验证凭据检查、下载、清理和识别调用。

修改：

- `DeanConversionTool/Models/MusicAnalysis.swift`：增加机器可读结果状态和提交样本数量，并兼容旧历史文件。
- `DeanConversionTool/Services/MusicAnalysisService.swift`：为每种执行结果写入准确状态。
- `DeanConversionTool/Services/HistoryProjectStore.swift`：覆盖更新现有项目的音乐分析文件。
- `DeanConversionTool/Services/SettingsWindowController.swift`：支持直接打开背景音乐设置区域。
- `DeanConversionTool/Views/SettingsView.swift`：根据入口选择“功能”页并滚动到背景音乐配置。
- `DeanConversionTool/ViewModels/TranscriptViewModel.swift`：增加音乐重试状态、设置入口和重试协调逻辑。
- `DeanConversionTool/Views/PropertiesPanel.swift`：根据识别状态显示正确提示和快捷操作。
- `DeanConversionToolTests/MusicAnalysisModelTests.swift`：验证新字段和旧文件兼容。
- `DeanConversionToolTests/MusicAnalysisServiceTests.swift`：验证未配置、成功、未命中和失败状态。
- `DeanConversionToolTests/HistoryMusicAnalysisTests.swift`：验证覆盖同一项目且不增加项目数量。

## 任务 1：增加机器可读的音乐识别状态

**文件：**

- 修改：`DeanConversionTool/Models/MusicAnalysis.swift`
- 修改：`DeanConversionTool/Services/MusicAnalysisService.swift`
- 测试：`DeanConversionToolTests/MusicAnalysisModelTests.swift`
- 测试：`DeanConversionToolTests/MusicAnalysisServiceTests.swift`

- [ ] **步骤 1：先编写失败测试**

在模型测试中增加：

```swift
func testOldMusicAnalysisJSONDefaultsToCompletedOutcome() throws {
    let data = """
    {
      "sourceURL": "https://example.com/video",
      "createdAt": "2026-06-08T08:00:00Z",
      "scanMode": "quick",
      "tracks": [],
      "unmatchedSampleCount": 0
    }
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let analysis = try decoder.decode(MusicAnalysis.self, from: data)

    XCTAssertEqual(analysis.outcome, .completed)
    XCTAssertEqual(analysis.submittedSampleCount, 0)
}
```

在服务测试中分别断言：

```swift
XCTAssertEqual(analysis.outcome, .notConfigured)
XCTAssertEqual(analysis.submittedSampleCount, 0)
```

以及：

```swift
XCTAssertEqual(analysis.outcome, .completed)
XCTAssertEqual(analysis.submittedSampleCount, 3)
```

- [ ] **步骤 2：运行测试并确认失败原因正确**

运行：

```bash
xcodegen generate
xcodebuild -project DeanConversionTool.xcodeproj \
  -scheme DeanConversionTool \
  -configuration Debug \
  -only-testing:DeanConversionToolTests/MusicAnalysisModelTests \
  -only-testing:DeanConversionToolTests/MusicAnalysisServiceTests \
  test
```

预期：编译失败，提示 `MusicAnalysis` 没有 `outcome` 或 `submittedSampleCount`。

- [ ] **步骤 3：实现最小模型与状态映射**

增加：

```swift
enum MusicAnalysisOutcome: String, Codable, Equatable {
    case notConfigured
    case completed
    case partialFailure
    case failed
}
```

为 `MusicAnalysis` 增加显式初始化和自定义解码：

```swift
let outcome: MusicAnalysisOutcome
let submittedSampleCount: Int
```

旧文件缺少字段时：

```swift
outcome = try container.decodeIfPresent(
    MusicAnalysisOutcome.self,
    forKey: .outcome
) ?? .completed
submittedSampleCount = try container.decodeIfPresent(
    Int.self,
    forKey: .submittedSampleCount
) ?? 0
```

`MusicAnalysisService` 使用以下规则：

- 未配置提供方：`.notConfigured`
- 样本提取失败：`.failed`
- 所有调用正常结束，包括零匹配：`.completed`
- 部分样本调用失败且仍有歌曲结果：`.partialFailure`
- 所有样本调用失败且没有歌曲结果：`.failed`

- [ ] **步骤 4：运行目标测试并确认通过**

运行步骤 2 的命令。

预期：两个测试类全部通过。

- [ ] **步骤 5：提交**

```bash
git add \
  DeanConversionTool/Models/MusicAnalysis.swift \
  DeanConversionTool/Services/MusicAnalysisService.swift \
  DeanConversionToolTests/MusicAnalysisModelTests.swift \
  DeanConversionToolTests/MusicAnalysisServiceTests.swift
git commit -m "feat: track music recognition outcomes"
```

## 任务 2：支持覆盖更新当前历史项目

**文件：**

- 修改：`DeanConversionTool/Services/HistoryProjectStore.swift`
- 测试：`DeanConversionToolTests/HistoryMusicAnalysisTests.swift`

- [ ] **步骤 1：先编写失败测试**

增加测试：

```swift
func testUpdatesMusicAnalysisWithoutCreatingAnotherProject() throws {
    let project = try store.saveTranscriptProject(
        transcript: transcript(),
        sourceType: .onlineVideo
    )
    let updated = try store.updateMusicAnalysis(analysis(), for: project)

    XCTAssertEqual(try store.loadProjects().count, 1)
    XCTAssertEqual(updated.id, project.id)
    XCTAssertEqual(updated.outputs.musicAnalysisJSON, "music-analysis.json")
    XCTAssertEqual(try store.loadMusicAnalysis(for: updated), analysis())
}
```

- [ ] **步骤 2：运行测试并确认失败**

运行：

```bash
xcodegen generate
xcodebuild -project DeanConversionTool.xcodeproj \
  -scheme DeanConversionTool \
  -configuration Debug \
  -only-testing:DeanConversionToolTests/HistoryMusicAnalysisTests \
  test
```

预期：编译失败，提示不存在 `updateMusicAnalysis(_:for:)`。

- [ ] **步骤 3：实现现有项目覆盖更新**

在 `HistoryProjectStore` 中增加：

```swift
func updateMusicAnalysis(
    _ analysis: MusicAnalysis,
    for project: HistoryProject
) throws -> HistoryProject {
    let fileName = "music-analysis.json"
    try writeMusicAnalysis(
        analysis,
        to: project.projectURL.appendingPathComponent(fileName)
    )

    var updated = project
    updated.outputs.musicAnalysisJSON = fileName
    updated.updatedAt = Date()
    try writeProjectMetadata(updated)
    return updated
}
```

该方法只能写入 `project.projectURL`，不能调用 `saveTranscriptProject`。

- [ ] **步骤 4：运行测试并确认通过**

运行步骤 2 的命令。

预期：`HistoryMusicAnalysisTests` 全部通过，项目数量仍为 1。

- [ ] **步骤 5：提交**

```bash
git add \
  DeanConversionTool/Services/HistoryProjectStore.swift \
  DeanConversionToolTests/HistoryMusicAnalysisTests.swift
git commit -m "feat: update music results in existing projects"
```

## 任务 3：实现独立的背景音乐重试服务

**文件：**

- 新增：`DeanConversionTool/Services/MusicRecognitionRetryService.swift`
- 新增：`DeanConversionToolTests/MusicRecognitionRetryServiceTests.swift`

- [ ] **步骤 1：先编写失败测试**

用内存凭据、下载器和样本服务验证：

```swift
func testMissingCredentialsStopsBeforeDownload() async {
    let downloader = FakeRetryDownloader()
    let service = MusicRecognitionRetryService(
        credentialStore: MemoryCredentialStore(credentials: nil),
        downloader: downloader,
        sampleProducer: FakeSampleProducer(result: []),
        providerFactory: { _ in FakeMusicProvider(responses: []) }
    )

    do {
        _ = try await service.retry(
            sourceURL: URL(string: "https://example.com/video")!,
            transcript: transcript(),
            mode: .quick,
            cookieSource: .none
        )
        XCTFail("预期缺少凭据错误")
    } catch {
        XCTAssertEqual(error as? MusicRecognitionRetryError, .missingCredentials)
    }

    XCTAssertEqual(downloader.downloadCount, 0)
}
```

再增加成功测试，断言：

```swift
XCTAssertEqual(downloader.downloadCount, 1)
XCTAssertEqual(downloader.cleanupCount, 1)
XCTAssertEqual(result.outcome, .completed)
```

- [ ] **步骤 2：运行测试并确认失败**

运行：

```bash
xcodegen generate
xcodebuild -project DeanConversionTool.xcodeproj \
  -scheme DeanConversionTool \
  -configuration Debug \
  -only-testing:DeanConversionToolTests/MusicRecognitionRetryServiceTests \
  test
```

预期：编译失败，提示重试服务和相关协议不存在。

- [ ] **步骤 3：实现最小重试服务**

定义只覆盖重试所需能力的协议：

```swift
protocol MusicRetryAudioDownloading {
    func downloadAudio(
        from urlString: String,
        cookieSource: OnlineVideoCookieSource
    ) async throws -> OnlineVideoDownload

    func cleanup(download: OnlineVideoDownload)
}
```

默认下载器在后台线程调用现有同步服务：

```swift
final class OnlineVideoMusicRetryDownloader: MusicRetryAudioDownloading {
    func downloadAudio(
        from urlString: String,
        cookieSource: OnlineVideoCookieSource
    ) async throws -> OnlineVideoDownload {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(
                        returning: try OnlineVideoService().downloadAudio(
                            from: urlString,
                            cookieSource: cookieSource
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func cleanup(download: OnlineVideoDownload) {
        OnlineVideoService().cleanup(download: download)
    }
}
```

`MusicRecognitionRetryService.retry` 必须依次：

1. 读取并验证完整凭据。
2. 下载临时音频。
3. 用 `defer` 清理临时音频。
4. 创建 `XFYunMusicRecognitionProvider`。
5. 调用 `MusicAnalysisService`，传入现有字幕片段。

错误类型：

```swift
enum MusicRecognitionRetryError: LocalizedError, Equatable {
    case missingCredentials
}
```

该服务不得持有或调用 `WhisperService`、`AudioPreprocessingService` 或 `SpeakerDiarizationService`。

- [ ] **步骤 4：运行测试并确认通过**

运行步骤 2 的命令。

预期：缺少凭据时下载次数为 0；成功时下载和清理各执行一次。

- [ ] **步骤 5：提交**

```bash
git add \
  DeanConversionTool/Services/MusicRecognitionRetryService.swift \
  DeanConversionToolTests/MusicRecognitionRetryServiceTests.swift
git commit -m "feat: add isolated music recognition retry service"
```

## 任务 4：支持直接打开背景音乐配置

**文件：**

- 修改：`DeanConversionTool/Services/SettingsWindowController.swift`
- 修改：`DeanConversionTool/Views/SettingsView.swift`

- [ ] **步骤 1：定义设置入口**

增加：

```swift
enum SettingsDestination {
    case general
    case musicRecognition
}
```

将控制器入口调整为：

```swift
func show(
    destination: SettingsDestination = .general,
    relativeTo parentWindow: NSWindow?
)
```

- [ ] **步骤 2：让设置视图根据入口定位**

`SettingsView` 初始化时：

```swift
init(destination: SettingsDestination = .general) {
    self.destination = destination
    _selectedSection = State(
        initialValue: destination == .musicRecognition ? .features : .general
    )
}
```

使用 `ScrollViewReader`，为背景音乐设置组添加：

```swift
.id("music-recognition-settings")
```

当入口是 `.musicRecognition` 时，在视图出现后滚动到该标识。

- [ ] **步骤 3：重新构造窗口根视图**

每次调用 `show` 时，将窗口内容更新为：

```swift
NSHostingView(rootView: SettingsView(destination: destination))
```

确保从主界面打开设置仍默认进入“通用”，从“立即设置”进入时直接显示背景音乐配置。

- [ ] **步骤 4：编译验证**

运行：

```bash
xcodegen generate
xcodebuild -project DeanConversionTool.xcodeproj \
  -scheme DeanConversionTool \
  -configuration Debug \
  build
```

预期：构建成功。

- [ ] **步骤 5：提交**

```bash
git add \
  DeanConversionTool/Services/SettingsWindowController.swift \
  DeanConversionTool/Views/SettingsView.swift
git commit -m "feat: open music recognition settings directly"
```

## 任务 5：接入重新识别与结果区操作

**文件：**

- 修改：`DeanConversionTool/ViewModels/TranscriptViewModel.swift`
- 修改：`DeanConversionTool/Views/PropertiesPanel.swift`

- [ ] **步骤 1：增加独立音乐任务状态**

在 `TranscriptViewModel` 中增加：

```swift
@Published var isRetryingMusicRecognition = false
@Published var musicRecognitionProgressMessage: String?
```

增加：

```swift
func openMusicRecognitionSettings() {
    SettingsWindowController.shared.show(
        destination: .musicRecognition,
        relativeTo: NSApp.keyWindow ?? NSApp.mainWindow
    )
}
```

- [ ] **步骤 2：实现重新识别协调**

增加 `retryMusicRecognition()`：

```swift
func retryMusicRecognition() {
    guard !isRetryingMusicRecognition,
          let transcript,
          !transcript.sourceURL.isFileURL else { return }

    let mode = musicAnalysis?.scanMode ?? musicScanMode
    guard mode != .off else { return }

    isRetryingMusicRecognition = true
    musicAnalysisMessage = nil
    musicAnalysisIsError = false

    Task {
        defer {
            isRetryingMusicRecognition = false
            musicRecognitionProgressMessage = nil
        }

        do {
            let analysis = try await musicRetryService.retry(
                sourceURL: transcript.sourceURL,
                transcript: transcript,
                mode: mode,
                cookieSource: onlineVideoCookieSource
            ) { completed, total in
                Task { @MainActor in
                    self.musicRecognitionProgressMessage =
                        "正在识别背景音乐 \(completed)/\(total)..."
                }
            }

            guard analysis.outcome != .failed else {
                musicAnalysisMessage = analysis.warning ?? "背景音乐识别失败"
                musicAnalysisIsError = true
                return
            }

            musicAnalysis = analysis
            try updateCurrentProjectMusicAnalysis(analysis)
            musicAnalysisMessage = analysis.tracks.isEmpty
                ? "背景音乐扫描完成，暂未识别到歌曲"
                : "已识别 \(analysis.tracks.count) 首背景音乐"
            musicAnalysisIsError = analysis.outcome == .partialFailure
        } catch MusicRecognitionRetryError.missingCredentials {
            musicAnalysisMessage = "尚未配置讯飞识曲凭据"
            musicAnalysisIsError = true
            openMusicRecognitionSettings()
        } catch {
            musicAnalysisMessage = "背景音乐重新识别失败：\(error.localizedDescription)"
            musicAnalysisIsError = true
        }
    }
}
```

项目覆盖逻辑必须：

```swift
if let project = selectedHistoryProject {
    let updated = try historyStore.updateMusicAnalysis(analysis, for: project)
    historyProjects.removeAll { $0.id == updated.id }
    historyProjects.append(updated)
    historyProjects.sort { $0.updatedAt > $1.updatedAt }
    selectedProjectID = updated.id
}
```

不得调用 `processOnlineVideo`、`processFileInternal`、`transcribeAudio` 或 `archiveTranscript`。

- [ ] **步骤 3：根据状态调整右侧面板**

状态为 `.notConfigured` 时：

- 不显示“暂未识别到歌曲”。
- 不显示“未命中样本”。
- 显示“尚未配置讯飞识曲凭据”。
- 显示“立即设置”和“重新识别”。

状态为 `.completed` 且没有歌曲时：

- 显示“暂未识别到歌曲”。
- 显示“重新识别”。

状态为 `.failed` 或 `.partialFailure` 时：

- 显示具体错误。
- 保留现有歌曲行。
- 显示“重新识别”。

只有满足以下条件时显示未命中数量：

```swift
analysis.submittedSampleCount > 0
```

重试中按钮标题显示：

```swift
"正在识别..."
```

并禁用重复点击。为 `PropertyButton` 增加默认值为 `false` 的 `isDisabled` 参数。

- [ ] **步骤 4：运行全部单元测试**

运行：

```bash
xcodegen generate
xcodebuild -project DeanConversionTool.xcodeproj \
  -scheme DeanConversionTool \
  -configuration Debug \
  test
```

预期：全部测试通过。

- [ ] **步骤 5：运行应用构建和流水线检查**

运行：

```bash
xcodebuild -project DeanConversionTool.xcodeproj \
  -scheme DeanConversionTool \
  -configuration Debug \
  build
./test_pipeline.sh
```

预期：Debug 构建和项目流水线通过。

- [ ] **步骤 6：启动并手动验证界面**

验证：

1. 未配置凭据的项目显示“立即设置”，不显示“未命中样本”。
2. “立即设置”直接打开背景音乐配置区域。
3. 保存凭据后设置窗口不自动开始识别。
4. 回到项目点击“重新识别”时字幕保持显示。
5. 识别完成后当前历史项目数量不增加。

- [ ] **步骤 7：提交**

```bash
git add \
  DeanConversionTool/ViewModels/TranscriptViewModel.swift \
  DeanConversionTool/Views/PropertiesPanel.swift
git commit -m "feat: add music recognition recovery actions"
```

## 最终验收

- [ ] `git diff --check` 无错误。
- [ ] 全部 XCTest 通过。
- [ ] macOS Debug 构建通过。
- [ ] `./test_pipeline.sh` 通过。
- [ ] 工作区只包含本功能相关修改。
- [ ] “重新识别”代码路径中不存在 Whisper、说话人识别或新建历史项目调用。
