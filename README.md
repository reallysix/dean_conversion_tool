# Dean Conversion Tool

[English Documentation](README_EN.md)

Dean Conversion Tool 是一款 macOS 原生音视频转文字工具。它基于 `whisper.cpp` 在本地完成转写，支持可选的说话人识别，并可以将逐字稿导出为 SRT、TXT、Markdown、HTML 和 JSON。

## 功能亮点

- 本地转写：通过 `whisper-cli` 调用 whisper.cpp，无需把音频上传到云端。
- 音视频导入：支持拖拽导入常见音频和视频文件。
- 说话人识别：可通过 `pyannote.audio` 为转写片段匹配说话人标签。
- 批量处理：支持多文件批量转写并自动导出。
- 在线视频：支持粘贴 `yt-dlp` 可解析的公开视频链接，输入时显示平台识别状态，失败后可直接重试。
- 背景音乐识别：在线视频转写可选快速或深度扫描，优先读取平台音乐标注，再通过讯飞 ACRCloud 识别短音频样本。
- 历史记录：按视频标题归档转写结果、字幕和文本文件，并保存在线视频的标题、原始链接、平台和创建时间。
- 环境检查：右侧任务状态会统一显示 Whisper、模型、FFmpeg、`yt-dlp`、`deno` 和可选说话人识别状态，缺失命令行依赖时可确认后一键安装。
- 模型下载：模型缺失时可在应用内下载，并显示模型大小、保存位置、下载进度、取消、失败重试和下载源入口。
- 视频预览：本地视频文件可在应用内播放；在线视频会通过 `yt-dlp` 解析可播放地址并在应用内播放，播放器使用模糊背景填充黑边并保留完整画面比例。
- 播放联动：点击时间戳或文本片段可跳转到对应视频时间；播放过程中会自动高亮当前字幕片段并跟随滚动。
- 多格式导出：支持 SRT、TXT、Markdown、HTML、JSON。
- 原生界面：SwiftUI 构建，采用左侧历史、中央工作区、右侧任务状态的工作台布局，并补充空状态、处理中状态和完成状态。

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

如果用户明确希望通过 Homebrew 安装缺失工具，可以在 App 右侧「环境」区域点击缺失项的「点击安装」，或手动运行：

```bash
Scripts/check_dependencies.sh --install
```

当前策略是：App 不会在首次启动时静默调用 Homebrew 自动安装依赖。应用会在右侧“环境”区域检测缺失项，只有用户确认后才会调用 `Scripts/check_dependencies.sh --install`；打包脚本会默认运行 `Scripts/check_dependencies.sh` 做本机依赖检查。

说话人识别依赖 Hugging Face 模型授权。首次使用前可能需要登录 Hugging Face 并接受 pyannote 模型许可。

## 配置背景音乐识别

第一版使用讯飞 ACRCloud，面向个人、非商业测试。先在讯飞开放平台创建支持音乐识别的应用，取得 `APPID`、`APIKey` 和 `APISecret`，然后在 App 的“设置 → 功能 → 背景音乐识别”中保存。凭据只保存在当前 Mac 的系统钥匙串，设置页不会回显已保存的值。

在线视频区域提供三种模式：

- 关闭：不做背景音乐分析，也不上传音乐样本。
- 快速识别：最多提取 3 段约 8 秒的 MP3 样本。
- 深度识别：按时间区间最多提取 10 段约 8 秒的 MP3 样本。

识别会先使用视频平台返回的歌曲和歌手元数据，再调用讯飞补充识别。音频样本会发送给讯飞；临时下载音频和样本会在任务结束后删除。识曲失败只显示警告，不会让转写任务失败。结果会随历史项目保存为 `music-analysis.json`，也可单独导出 JSON 或 TXT。

部分抖音、小红书等链接可能要求登录。可在“设置 → 功能 → 在线视频登录状态”中选择“Chrome 登录状态”，让 `yt-dlp` 临时使用 `--cookies-from-browser chrome`。App 不保存平台密码，不复制 Cookie 内容，也不会把 Cookie 写入历史项目。

开发测试版从本机直接请求讯飞接口。公开发布或商业使用前，应将 `MusicRecognitionProvider` 替换为服务端代理，避免在客户端分发供应商凭据，并重新确认服务条款、隐私披露和调用费用。

## 下载 Whisper 模型

应用右侧「环境」区域会在模型缺失时显示模型信息和「下载模型」，可直接在应用内下载到默认目录。当前版本固定使用 `Whisper large-v3`，模型文件约 3.1GB。

```bash
./download_model.sh
```

应用内下载和脚本都会将 large-v3 模型保存到：

```text
~/Library/Application Support/DeanConversion/models/
```

如果下载失败，右侧「环境」区域会保留失败原因并提供「重试下载」。也可以点击「下载源」在浏览器中打开 Hugging Face 模型地址。

第一版安装包不内置 Whisper 模型，避免 DMG 体积过大。正式发布默认策略是安装后按需下载 `Whisper large-v3`。

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

默认生成本地未签名 `.dmg`，用于安装包流程和非 Xcode 启动验证：

```bash
Scripts/package_app.sh
```

输出路径：

```text
build/package/Release/Dean Conversion Tool.dmg
```

打包脚本会先检查本机依赖、生成 Xcode 项目、构建 Release `.app`、校验必要资源，然后创建 DMG。

如果要生成正式签名版本，先复制示例配置并填入 Apple Developer 信息：

```bash
cp Scripts/release_config.example.env Scripts/release_config.env
open Scripts/release_config.env
```

然后运行：

```bash
Scripts/package_app.sh
```

如果已经在本机钥匙串保存了 notarization 凭据，可以同时提交公证：

```bash
Scripts/package_app.sh --notarize
```

`Scripts/release_config.env` 不会提交到 Git。需要配置的值包括正式 Bundle ID、Apple Team ID、Developer ID Application 证书名和 `notarytool` profile。

## 使用流程

1. 启动应用。
2. 在右侧“环境”区域确认核心依赖和模型状态。
3. 点击导入按钮，或将音频/视频文件拖入窗口；也可以在在线链接输入框粘贴公开的视频链接。在线视频输入框会显示链接格式和平台识别状态。
   - 如需识别背景音乐，选择“快速识别”或“深度识别”。
4. 等待处理流程完成：
   - 在线视频音频下载
   - 音频预处理
   - Whisper 转写
   - 说话人识别，可选
   - 背景音乐识别，可选
5. 浏览逐字稿、搜索内容和选择片段。点击时间戳或文本片段可让本地播放器跳转；YouTube 在线预览也会同步跳转。播放过程中当前字幕片段会自动高亮并跟随滚动。
6. 导出为需要的格式。选择目录后，应用会显示导出结果和最终保存路径。

历史项目默认保存在：

```text
~/Documents/DeanConversionTool/Projects
```

应用会自动创建目录。历史记录只保存源路径或源链接、在线视频元数据，以及生成的转写、字幕和文本结果。

## 支持格式

输入格式：

- 音频：MP3、WAV、M4A、AAC、FLAC、OGG、WMA
- 视频：MP4、MOV、AVI、MKV、WebM、M4V
- 在线视频：`yt-dlp` 支持解析的链接，例如 YouTube、B 站、抖音、小红书等

导出格式：

- SRT：字幕剪辑工作流
- TXT：纯文本逐字稿
- Markdown：带时间戳和说话人标签的文档
- HTML：可浏览的网页版本
- JSON：结构化数据
- 音乐分析：单独导出 JSON 或 TXT 歌曲列表

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

## 路线图

- 逐字级时间轴与正在念的文字高亮。
- 进一步优化右侧任务状态在低高度窗口下的信息密度。
- 优化文稿列表行高、段落 hover 态、历史标题截断提示和顶部媒体区层级。

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

当前版本聚焦转写、可选背景音乐识别、说话人识别、批量处理和导出。背景音乐识别第一版仅用于个人非商业测试。情感分析功能已从项目范围中移除。

## License

Copyright © 2026 Dean. All rights reserved.

## Acknowledgments

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
- [pyannote.audio](https://github.com/pyannote/pyannote-audio)
- [FFmpeg](https://ffmpeg.org/)
