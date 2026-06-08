# 在线视频背景音乐识别设计

## 状态

- 日期：2026-06-08
- 状态：已确认方向，等待书面复核
- 首版用途：个人测试、仅限非商业使用

## 目标

在现有在线视频转写流程中增加一个可选的“同时识别背景音乐”能力。用户粘贴抖音、小红书、B 站或其他 `yt-dlp` 可解析的公开视频链接后，可以在转写前勾选该选项。处理完成后，应用列出平台标注或音频指纹匹配到的歌曲，并保存到历史项目。

首版优先保持零按次费用：

1. 优先读取 `yt-dlp` 返回的平台音乐元数据。
2. 元数据不足时，使用 AcoustID 公共服务做补充识别。
3. AcoustID 只用于本项目的个人、非商业测试版本。
4. 商业发布前，必须替换为 ShazamKit、取得 AcoustID 商业授权，或选择其他允许商业使用的服务。

## 非目标

首版不包含：

- 本地音频或本地视频的背景音乐识别。
- 应用内抖音、小红书或 B 站登录页面。
- 保存平台账号、密码或持久化 Cookie 文件。
- 私密视频、付费视频或用户无权访问内容的下载。
- Demucs 等人声/伴奏分离模型。
- 音乐下载、播放列表管理或版权内容保存。
- 对识别结果做百分之百准确的承诺。

## 用户流程

### 无登录要求的视频

1. 用户在“在线视频”区域粘贴链接。
2. 用户选择是否勾选“同时识别背景音乐”。
3. 用户点击“解析并转写”。
4. 应用通过 `yt-dlp` 获取视频元数据并下载音频。
5. 应用完成文字转写。
6. 如果勾选音乐识别，应用先读取平台音乐标签，再对音频样本生成指纹并查询 AcoustID。
7. 转写结果正常显示；音乐结果显示在右侧属性面板的“背景音乐”区域。
8. 历史项目保存文稿文件和独立的音乐分析 JSON。

### 需要登录的视频

1. 默认不使用浏览器 Cookie。
2. 当 `yt-dlp` 明确返回登录或 Cookie 错误时，应用提示用户先在 Chrome 中登录对应平台。
3. 用户可在设置中将“在线视频登录状态”切换为“Chrome”。
4. 后续解析调用增加 `--cookies-from-browser chrome`。
5. 应用不读取、展示、复制或持久化 Cookie 内容，只保存用户选择的浏览器类型。

首版只提供“无”和“Chrome”两个选项。Safari、Edge、Firefox 以及指定浏览器 Profile 不在首版范围内。

## 界面设计

### 在线视频输入区

在现有链接输入框和“解析并转写”按钮之间增加：

```text
☐ 同时识别背景音乐
  使用平台音乐标签和 AcoustID。仅限个人、非商业测试。
```

默认不勾选，避免延长不需要音乐识别的转写任务。

### 处理进度

勾选后增加以下阶段提示：

- 正在读取平台音乐信息
- 正在选择音乐样本
- 正在生成音频指纹
- 正在查询歌曲信息
- 正在整理音乐结果

音乐识别是附加能力。识别失败时，转写仍然成功，音乐区域显示具体原因。

### 结果区域

右侧属性面板增加“背景音乐”区域，每首歌曲显示：

- 歌曲名
- 歌手或艺术家
- 预计出现时间
- 识别来源：平台标注或 AcoustID
- AcoustID 匹配分数，仅在服务返回时显示
- 外部链接，仅在服务返回可靠链接时显示

平台只标注一首“使用音乐”但视频内可能存在多首歌曲时，平台结果和音频识别结果可以同时展示。相同歌曲需要合并。

### 设置

“功能设置”增加：

- AcoustID API Key 输入和清除操作。
- 非商业使用限制说明。
- “在线视频登录状态”：无、Chrome。
- Cookie 安全说明：应用不保存密码或 Cookie，由 `yt-dlp` 在解析时从浏览器读取。

AcoustID API Key 保存在 macOS Keychain，不写入 `UserDefaults`、项目历史或日志。

## 数据模型

新增独立于 `Transcript` 的音乐分析模型，避免把歌曲结果混入文字片段。

```swift
enum MusicRecognitionSource: String, Codable {
    case platformMetadata
    case acoustID
    case shazamKit
}

struct RecognizedTrack: Identifiable, Codable {
    let id: UUID
    let title: String
    let artist: String?
    let startTime: TimeInterval?
    let endTime: TimeInterval?
    let confidence: Double?
    let source: MusicRecognitionSource
    let externalURL: URL?
    let providerRecordingID: String?
}

struct MusicAnalysis: Codable {
    let sourceURL: URL
    let createdAt: Date
    let tracks: [RecognizedTrack]
    let unmatchedSampleCount: Int
    let providerName: String?
    let warning: String?
}
```

时间范围是基于采样窗口估算的结果。平台元数据通常没有时间范围，因此对应字段允许为 `nil`。

## 服务边界

### 音频识别 Provider

首版保留一个最小可替换接口：

```swift
struct MusicAudioSample {
    let id: UUID
    let audioURL: URL
    let startTime: TimeInterval
    let duration: TimeInterval
}

struct MusicMatch {
    let providerRecordingID: String
    let title: String
    let artist: String?
    let confidence: Double?
    let externalURL: URL?
}

protocol MusicRecognitionProvider {
    var name: String { get }

    func recognize(sample: MusicAudioSample) async throws -> [MusicMatch]
}
```

首版实现 `AcoustIDMusicRecognitionProvider`。后续启用付费 Apple Developer Program 后，新增 `ShazamKitMusicRecognitionProvider`，不修改采样、结果合并、UI、历史存储或导出逻辑。

平台音乐标签不实现这个协议，因为它不是音频指纹识别。它由 `OnlineVideoService` 的元数据解析结果直接交给音乐分析协调服务。

### 服务职责

- `OnlineVideoService`
  - 通过 `yt-dlp --dump-single-json` 获取标题、平台、`track`、`artist` 等元数据。
  - 根据设置决定是否添加 `--cookies-from-browser chrome`。
  - 下载音频并返回音频 URL 与平台元数据。

- `MusicSampleService`
  - 使用 FFmpeg 从已下载音频提取短样本。
  - 只创建临时文件，并在分析结束后删除。

- `AcoustIDMusicRecognitionProvider`
  - 调用 `fpcalc` 为传入样本生成 Chromaprint 指纹。
  - 向 AcoustID Lookup API 发送指纹、样本时长、API Key 和所需元数据参数。
  - 不上传原始音频。
  - 串行查询，确保不超过公共服务每秒 3 次请求的限制。

- `MusicAnalysisService`
  - 接收平台元数据、音频 URL、视频时长和转写片段。
  - 选择采样窗口。
  - 调用当前 `MusicRecognitionProvider`。
  - 合并平台结果、重复指纹结果和相邻时间窗口。
  - 返回统一的 `MusicAnalysis`。

- `CredentialStore`
  - 使用 macOS Keychain 保存和删除 AcoustID API Key。

## 采样与识别策略

首版使用原始混合音频，不做人声分离。

原因：

- Demucs 会增加 Python、PyTorch、模型体积和运行时间。
- 去除口播时可能同时去除歌曲演唱人声，反而降低识别率。
- AcoustID 首版本身属于实验性补充能力，应先验证直接指纹效果。

采样规则：

1. 每个样本长度为 15 秒；不足 15 秒时使用剩余音频。
2. 以约 30 秒为间隔生成候选窗口。
3. 使用 Whisper 转写片段估算每个窗口的口播占比，在相邻候选位置中优先选择口播较少的窗口。
4. 最多查询 20 个样本，防止长视频产生无边界请求。
5. 样本按时间顺序串行查询，查询间隔不少于 350 毫秒。
6. 相同 `providerRecordingID` 的结果合并。
7. 相邻样本识别为同一首歌时，合并为一个预计时间范围。
8. AcoustID 分数低于 `0.80` 的结果计入未匹配样本，不显示为确定歌曲。

首版不根据音量自动判断“是否存在背景音乐”，因为对白、音效和压缩噪声容易造成误判。

## 依赖

现有依赖继续使用：

- `yt-dlp`
- FFmpeg / ffprobe
- `whisper-cli`

新增本地依赖：

- Chromaprint 的 `fpcalc`
- Homebrew 安装命令：`brew install chromaprint`

`Scripts/check_dependencies.sh` 需要把 `fpcalc` 标记为音乐识别的可选依赖。缺少 `fpcalc` 不影响普通转写。

网络依赖：

- AcoustID Lookup API

## 历史存储与导出

历史项目继续不保存下载的视频或音频。

勾选音乐识别后，项目目录增加：

```text
music-analysis.json
```

`ProjectOutputs` 增加可选的 `musicAnalysisJSON` 字段。旧项目没有该字段时仍能正常读取。

右侧属性面板提供：

- 导出音乐列表 JSON
- 导出音乐列表 TXT

JSON 使用 `MusicAnalysis` 的编码结果。TXT 按歌曲逐行输出名称、歌手、预计时间和来源。

## 错误处理

以下错误只影响音乐识别，不使转写失败：

- 未配置 AcoustID API Key。
- 未安装 `fpcalc`。
- AcoustID 网络失败、限流或服务不可用。
- 所有样本均未匹配。
- 单个样本提取或指纹生成失败。

如果平台元数据已经提供歌曲，即使 AcoustID 失败，仍显示平台结果，并附带补充识别失败提示。

以下错误仍按现有在线视频流程处理：

- 链接无效。
- `yt-dlp` 不支持链接。
- 视频私密、下架或地区受限。
- 登录态不足。
- 音频下载失败。

启用 Chrome Cookie 后仍失败时，不尝试保存或人工修改 Cookie，只展示 `yt-dlp` 整理后的错误信息。

## 隐私与授权

- AcoustID 查询上传的是 Chromaprint 指纹和样本时长，不上传原始音频文件。
- 临时音频样本在分析结束后删除。
- API Key 存入 macOS Keychain。
- 应用不保存平台账号密码。
- 应用不导出或长期保存浏览器 Cookie。
- Chrome Cookie 只在用户主动选择后由 `yt-dlp` 按次读取。
- 用户只能处理自己有权访问的内容。
- UI 和 README 必须注明：AcoustID 公共服务仅用于个人、非商业测试。

商业发布前必须完成一次发布审计，移除或替换 AcoustID 公共服务实现，并重新评估平台 Cookie 功能的合规说明。

## ShazamKit 迁移

后续具备 Apple Developer Program 会员和签名条件后：

1. 启用 ShazamKit capability 和应用签名。
2. 新增 `ShazamKitMusicRecognitionProvider`。
3. 将默认 Provider 从 AcoustID 切换为 ShazamKit。
4. 保留 `MusicAnalysis` 和 `RecognizedTrack` 数据格式。
5. 继续使用现有采样、结果合并、UI、历史存储和导出流程。
6. 移除 AcoustID 非商业提示和 `fpcalc` 必需路径；是否保留 AcoustID 仅由届时授权决定。

## 验证策略

### 单元测试

- 解析包含和不包含 `track`、`artist` 的 `yt-dlp` JSON。
- Chrome Cookie 参数只在用户选择后加入。
- 采样窗口不超过 20 个，短视频不会产生越界窗口。
- 口播较少的窗口优先。
- 相同歌曲结果去重并合并时间范围。
- AcoustID 低分和空结果不会生成确定歌曲。
- 缺少 API Key、`fpcalc` 或网络失败时返回非致命警告。
- 旧版 `project.json` 在缺少音乐输出字段时仍可解码。

### 集成验证

- 抖音公开视频：有平台音乐标签时可以显示。
- 小红书公开视频：无平台标签时可进入 AcoustID 补充流程。
- B 站公开视频：可下载音频并完成采样。
- Chrome 已登录场景：`--cookies-from-browser chrome` 可以处理需要登录但用户有权访问的视频。
- 未勾选音乐识别时，现有转写行为、耗时和历史文件不受影响。
- 音乐识别失败时，文稿仍然归档成功。

### 构建验证

```bash
xcodegen generate
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -configuration Debug build
./test_pipeline.sh
Scripts/check_dependencies.sh
```

## 验收标准

第一版完成的判定条件：

1. 在线视频区域可以选择是否同时识别背景音乐，默认关闭。
2. 抖音、小红书和 B 站的公开视频继续使用现有 `yt-dlp` 流程。
3. 平台音乐标签存在时，无需 AcoustID 也能显示结果。
4. 配置 API Key 且安装 `fpcalc` 后，应用能对选定样本查询 AcoustID。
5. 音乐结果包含名称、歌手、来源和可用的预计时间。
6. 音乐识别失败不会导致转写失败。
7. 历史项目可保存并重新加载 `music-analysis.json`。
8. 用户可以导出音乐结果为 JSON 和 TXT。
9. 用户可以选择按次读取 Chrome 登录状态，应用不保存密码或 Cookie。
10. UI 和文档明确标注 AcoustID 仅限个人、非商业测试。
11. 未来接入 ShazamKit 时不需要改动 UI、历史模型或分析协调流程。
