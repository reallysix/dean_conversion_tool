# Dean Conversion Tool

[English Documentation](README_EN.md)

Dean Conversion Tool 是一款 macOS 原生音视频转文字工具。它基于 `whisper.cpp` 在本地完成转写，支持可选的说话人识别，并可以将逐字稿导出为 SRT、TXT、Markdown、HTML 和 JSON。

## 功能亮点

- 本地转写：通过 `whisper-cli` 调用 whisper.cpp，无需把音频上传到云端。
- 音视频导入：支持拖拽导入常见音频和视频文件。
- 说话人识别：可通过 `pyannote.audio` 为转写片段匹配说话人标签。
- 批量处理：支持多文件批量转写并自动导出。
- 在线视频：支持粘贴 `yt-dlp` 可解析的公开视频链接，并将原始链接保存到历史项目。
- 历史记录：按视频标题归档转写结果、字幕和文本文件，不复制原始音视频。
- 环境检查：右侧任务状态会统一显示 Whisper、模型、FFmpeg、`yt-dlp`、`deno` 和可选说话人识别状态。
- 模型下载：模型缺失时可在应用内下载，并显示下载进度、取消和目录入口。
- 视频预览：视频文件可在应用内播放，并按时间戳跳转。
- 多格式导出：支持 SRT、TXT、Markdown、HTML、JSON。
- 原生界面：SwiftUI 构建，适配 macOS 桌面工作流。

## 运行要求

- macOS 14.0 Sonoma 或更高版本
- Xcode 15 或更高版本
- Apple Silicon Mac 推荐
- Homebrew
- Python 3.13+，仅说话人识别需要
- 16GB RAM 推荐，尤其使用 large-v3 模型时

## 依赖安装

```bash
brew install whisper-cpp
brew install ffmpeg
brew install yt-dlp
brew install deno
brew install xcodegen
pip3 install --break-system-packages pyannote.audio torch torchaudio
```

也可以使用项目脚本检查必需命令行工具：

```bash
Scripts/check_dependencies.sh
```

如果用户明确希望通过 Homebrew 安装缺失工具，可以手动运行：

```bash
Scripts/check_dependencies.sh --install
```

当前策略是：App 不会在首次启动时静默调用 Homebrew 自动安装依赖。应用会在右侧“环境”区域检测缺失项，并提供可复制的安装命令；打包脚本会默认运行 `Scripts/check_dependencies.sh` 做本机依赖检查。

说话人识别依赖 Hugging Face 模型授权。首次使用前可能需要登录 Hugging Face 并接受 pyannote 模型许可。

## 下载 Whisper 模型

应用右侧「环境」区域会在模型缺失时显示「下载模型」，可直接在应用内下载到默认目录。

```bash
./download_model.sh
```

应用内下载和脚本都会将 large-v3 模型保存到：

```text
~/Library/Application Support/DeanConversion/models/
```

## 构建与启动

```bash
xcodegen generate
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/DeanConversionTool-*/Build/Products/Debug/"Dean Conversion Tool.app"
```

也可以生成项目后直接用 Xcode 打开：

```bash
open DeanConversionTool.xcodeproj
```

然后选择 `DeanConversionTool` scheme，按 `Cmd + R` 运行。

## 打包 DMG

当前支持生成本地未签名 `.dmg`，用于安装包流程和非 Xcode 启动验证：

```bash
Scripts/package_app.sh
```

输出路径：

```text
build/package/Release/Dean Conversion Tool.dmg
```

打包脚本会先检查本机依赖、生成 Xcode 项目、构建 Release `.app`、校验必要资源，然后创建 DMG。当前安装包还未做正式签名和 notarization 公证。

## 使用流程

1. 启动应用。
2. 在右侧“环境”区域确认核心依赖和模型状态。
3. 点击导入按钮，或将音频/视频文件拖入窗口；也可以在在线链接输入框粘贴公开的视频链接。
4. 等待处理流程完成：
   - 在线视频音频下载
   - 音频预处理
   - Whisper 转写
   - 说话人识别，可选
5. 浏览逐字稿、搜索内容、选择片段或跳转视频时间点。
6. 导出为需要的格式。选择目录后，应用会显示导出结果和最终保存路径。

历史项目默认保存在：

```text
~/Documents/DeanConversionTool/Projects
```

应用会自动创建目录。历史记录只保存源路径或源链接，以及生成的转写、字幕和文本结果。

## 支持格式

输入格式：

- 音频：MP3、WAV、M4A、AAC、FLAC、OGG、WMA
- 视频：MP4、MOV、AVI、MKV、WebM、M4V
- 在线视频：`yt-dlp` 支持解析的公开视频链接，例如 YouTube、B 站、抖音等公开链接

导出格式：

- SRT：字幕剪辑工作流
- TXT：纯文本逐字稿
- Markdown：带时间戳和说话人标签的文档
- HTML：可浏览的网页版本
- JSON：结构化数据

## 项目结构

```text
DeanConversionTool/
├── Models/
│   └── TranscriptSegment.swift
├── Services/
│   ├── AudioPreprocessingService.swift
│   ├── ExportService.swift
│   ├── HistoryProjectStore.swift
│   ├── ModelDownloadService.swift
│   ├── OnlineVideoService.swift
│   ├── SpeakerDiarizationService.swift
│   └── WhisperService.swift
├── ViewModels/
│   └── TranscriptViewModel.swift
├── Views/
│   ├── BatchSetupSheet.swift
│   ├── BottomBar.swift
│   ├── ContentView.swift
│   ├── NavSidebar.swift
│   ├── PropertiesPanel.swift
│   ├── SettingsView.swift
│   ├── Theme.swift
│   ├── TranscriptView.swift
│   ├── VideoPlayerView.swift
│   └── WorkspaceSidebar.swift
└── DeanConversionToolApp.swift

PythonHelpers/
└── speaker_diarization.py

Scripts/
├── check_dependencies.sh
└── package_app.sh
```

## 验证

```bash
xcodegen generate
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -configuration Debug build
```

打包验证：

```bash
Scripts/package_app.sh
```

集成测试脚本：

```bash
./test_pipeline.sh
```

`test_pipeline.sh` 会检查 whisper.cpp、FFmpeg、模型文件和 Python 说话人识别依赖。

## 常见问题

### 找不到 Whisper 模型

运行：

```bash
./download_model.sh
```

### 找不到 whisper-cli

确认已安装：

```bash
brew install whisper-cpp
which whisper-cli
```

### 找不到 FFmpeg

确认已安装：

```bash
brew install ffmpeg
which ffmpeg
```

### 找不到 yt-dlp

确认已安装：

```bash
brew install yt-dlp
which yt-dlp
```

### YouTube 解析提示缺少 JavaScript runtime

确认已安装：

```bash
brew install deno
which deno
```

### 说话人识别不可用

确认 Python 依赖可导入：

```bash
python3 -c "import pyannote.audio; print('OK')"
```

同时确认 Hugging Face token 和 pyannote 模型授权已配置。

## 当前范围

当前版本聚焦转写、说话人识别、批量处理和导出。情感分析功能已从项目范围中移除。

## License

Copyright © 2026 Dean. All rights reserved.

## Acknowledgments

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
- [pyannote.audio](https://github.com/pyannote/pyannote-audio)
- [FFmpeg](https://ffmpeg.org/)
