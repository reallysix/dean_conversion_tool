# 在线视频背景音乐识别设计

## 状态

- 日期：2026-06-08
- 状态：已确认，按讯飞歌曲识别 ACRCloud 方案修订
- 首版用途：个人开发与小规模测试
- 商业方向：正式发布时由自有后端代理识别请求并承载计费

## 目标

在现有在线视频转写流程中增加可选的“同时识别背景音乐”能力。用户粘贴抖音、小红书、B 站或其他 `yt-dlp` 可解析的视频链接后，可以选择快速或深度识别。处理完成后，应用列出平台标注或音频识别得到的歌曲，并保存到历史项目。

识别顺序：

1. 优先读取 `yt-dlp` 返回的平台音乐元数据。
2. 元数据不足时，使用讯飞开放平台“歌曲识别 ACRCloud”分析短音频样本。
3. 开发版直接调用讯飞大陆接口，凭证保存在本机 Keychain。
4. 正式公开发布前切换为自有后端代理，客户端不携带服务密钥。

## 非目标

首版不包含：

- 本地音频或本地视频的背景音乐识别。
- 应用内抖音、小红书或 B 站登录页面。
- 保存平台账号、密码或持久化 Cookie 文件。
- 私密视频、付费视频或用户无权访问内容的下载。
- Demucs 等人声和伴奏分离模型。
- 整段媒体上传到云端。
- 音乐下载、播放列表管理或版权内容保存。
- 腾讯云 MPS 整片音乐识别。
- 对识别结果作百分之百准确的承诺。

## 用户流程

### 无登录要求的视频

1. 用户在“在线视频”区域粘贴链接。
2. 用户选择“关闭”“快速识别”或“深度识别”。
3. 用户点击“解析并转写”。
4. 应用通过 `yt-dlp` 获取视频元数据并下载音频。
5. 应用完成文字转写。
6. 如果启用了音乐识别，应用先读取平台音乐标签，再选择口播较少的音频窗口并调用讯飞。
7. 转写结果正常显示；音乐结果显示在右侧属性面板的“背景音乐”区域。
8. 历史项目保存文稿文件和独立的音乐分析 JSON。

### 需要登录的视频

1. 默认不使用浏览器 Cookie。
2. 当 `yt-dlp` 明确返回登录或 Cookie 错误时，应用提示用户先在 Chrome 中登录对应平台。
3. 用户可在设置中将“在线视频登录状态”切换为“Chrome”。
4. 后续解析调用增加 `--cookies-from-browser chrome`。
5. 应用不读取、展示、复制或持久化 Cookie 内容，只保存用户选择的浏览器类型。

首版只提供“无”和“Chrome”两个选项。Safari、Edge、Firefox及指定浏览器 Profile 不在首版范围内。

## 界面设计

### 在线视频输入区

在现有链接输入框和“解析并转写”按钮之间增加识别模式选择：

```text
背景音乐：关闭 / 快速识别 / 深度识别

快速识别：最多分析 3 个片段，适合短视频
深度识别：每段时间区间取样，最多分析 10 个片段
```

默认关闭，避免延长不需要音乐识别的任务。

### 处理进度

启用后增加以下阶段提示：

- 正在读取平台音乐信息
- 正在选择音乐样本
- 正在提取音乐样本
- 正在识别第 N/M 个样本
- 正在整理音乐结果

音乐识别是附加能力。识别失败时，转写仍然成功，音乐区域显示具体原因。

### 结果区域

右侧属性面板增加“背景音乐”区域，每首歌曲显示：

- 歌曲名
- 歌手或艺术家
- 专辑，仅在服务返回时显示
- 预计出现时间
- 识别来源：平台标注或讯飞 ACRCloud
- 识别置信度

平台只标注一首“使用音乐”但视频内可能存在多首歌曲时，平台结果和音频识别结果可以同时展示。相同歌曲需要合并。

### 设置

“功能设置”增加：

- 讯飞 `APPID`、`APIKey`、`APISecret` 的配置状态。
- 保存、更新和清除识别凭证。
- “在线视频登录状态”：无、Chrome。
- Cookie 安全说明：应用不保存密码或 Cookie，由 `yt-dlp` 在解析时从浏览器读取。
- 开发版提示：当前凭证只存于本机；公开分发前必须改为后端代理。

三个讯飞凭证保存在 macOS Keychain，不写入 `UserDefaults`、项目历史或日志。输入界面只显示是否已配置，不回显完整密钥。

## 数据模型

新增独立于 `Transcript` 的音乐分析模型：

```swift
enum MusicRecognitionSource: String, Codable {
    case platformMetadata
    case xfyunACRCloud
    case backend
    case shazamKit
}

enum MusicScanMode: String, Codable, CaseIterable {
    case off
    case quick
    case deep
}

struct RecognizedTrack: Identifiable, Codable {
    let id: UUID
    let title: String
    let artist: String?
    let album: String?
    let startTime: TimeInterval?
    let endTime: TimeInterval?
    let confidence: Double?
    let source: MusicRecognitionSource
    let providerRecordingID: String?
}

struct MusicAnalysis: Codable {
    let sourceURL: URL
    let createdAt: Date
    let scanMode: MusicScanMode
    let tracks: [RecognizedTrack]
    let unmatchedSampleCount: Int
    let providerName: String?
    let warning: String?
}
```

时间范围是基于采样窗口和服务返回的 `play_offset_ms` 估算的结果。平台元数据通常没有时间范围，因此对应字段允许为 `nil`。

## 服务边界

### 音频识别 Provider

保留最小可替换接口：

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
    let album: String?
    let confidence: Double?
    let playOffset: TimeInterval?
}

protocol MusicRecognitionProvider {
    var name: String { get }

    func recognize(sample: MusicAudioSample) async throws -> [MusicMatch]
}
```

首版实现 `XFYunMusicRecognitionProvider`。正式发布时新增 `BackendMusicRecognitionProvider`，由它把样本发给自有后端；UI、采样、结果合并、历史存储和导出逻辑不变。未来启用 ShazamKit 时也沿用同一接口。

平台音乐标签不实现该协议，因为它不是音频识别。它由 `OnlineVideoService` 的元数据解析结果直接交给音乐分析协调服务。

### 服务职责

- `OnlineVideoService`
  - 通过 `yt-dlp --dump-single-json` 获取标题、平台、`track`、`artist` 等元数据。
  - 根据设置决定是否添加 `--cookies-from-browser chrome`。
  - 下载音频并返回音频 URL 与平台元数据。

- `MusicSampleService`
  - 使用 FFmpeg 从已下载音频提取 MP3 短样本。
  - 固定输出 16 kHz、单声道、16-bit、64 kbps MP3。
  - 检查 Base64 编码后不超过 1 MiB。
  - 只创建临时文件，并在分析结束后删除。

- `XFYunRequestSigner`
  - 按 RFC 1123 生成 GMT `date`。
  - 对 `host`、`date` 和 `request-line` 使用 HMAC-SHA256 签名。
  - 生成讯飞要求的 `authorization`、`host` 和 `date` 查询参数。

- `XFYunMusicRecognitionProvider`
  - 调用大陆音乐识别端点：
    `https://cn-east-1.api.xf-yun.com/v1/private/s29ebee0d`
  - 在 `payload.data` 中上传 Base64 音频和格式信息。
  - 解码响应中 `payload.output_text.text` 的 Base64 JSON。
  - 映射 `acrid`、`title`、`artists`、`album`、`play_offset_ms` 和 `score`。

- `MusicAnalysisService`
  - 接收平台元数据、音频 URL、视频时长、转写片段和扫描模式。
  - 选择采样窗口并调用 `MusicSampleService`。
  - 串行调用当前 `MusicRecognitionProvider`。
  - 合并平台结果、重复识别结果和相邻时间窗口。
  - 返回统一的 `MusicAnalysis`。

- `CredentialStore`
  - 使用 macOS Keychain 保存和删除讯飞三个凭证。

## 采样与识别策略

首版使用原始混合音频，不做人声分离。

原因：

- 人声分离会增加 Python、PyTorch、模型体积和运行时间。
- 去除口播时可能同时去除歌曲演唱人声，反而降低识别率。
- 讯飞 ACRCloud 本身针对含噪声和背景音乐场景，先验证直接采样效果更合理。

通用规则：

1. 每个样本长度为 8 秒；不足 8 秒时使用剩余音频。
2. 使用 Whisper 转写片段计算候选窗口的口播覆盖比例。
3. 每个时间区间在多个候选位置中选择口播覆盖最少的窗口。
4. 样本按时间顺序串行查询。
5. 相同 `providerRecordingID` 的结果合并。
6. 相邻样本识别为同一首歌时，合并为一个预计时间范围。
7. 讯飞分数低于 `70` 的结果计入未匹配样本，不显示为确定歌曲。
8. 单个样本失败后继续处理其余样本。

快速识别：

- 把视频划分为开头、中间和结尾三个区间。
- 每个区间最多选择一个样本。
- 最多调用 3 次。

深度识别：

- 以 45 秒为一个时间区间。
- 每个区间最多选择一个样本。
- 最多调用 10 次。

首版不根据音量自动判断是否存在背景音乐，因为对白、音效和压缩噪声容易造成误判。

## 讯飞请求约束

请求使用：

- 协议：HTTPS POST
- 端点：`https://cn-east-1.api.xf-yun.com/v1/private/s29ebee0d`
- 服务参数：`parameter.acr_music.mode = "music"`
- 音频节点：`payload.data`
- 音频编码：`lame`
- 采样率：`16000`
- 声道：`1`
- 位深：`16`
- 传输状态：`3`
- Base64 音频大小：不超过 `1048576` 字节

服务成功响应需要同时满足：

- 外层 `header.code == 0`
- Base64 解码后的结果 `status.code == 0`

## 依赖

现有依赖继续使用：

- `yt-dlp`
- FFmpeg / ffprobe
- `whisper-cli`

新增系统框架：

- `Security`：Keychain
- `CryptoKit`：HMAC-SHA256

不增加新的 Homebrew 依赖。

网络依赖：

- 讯飞开放平台歌曲识别 ACRCloud

## 历史存储与导出

历史项目继续不保存下载的视频或音频。

启用音乐识别后，项目目录增加：

```text
music-analysis.json
```

`ProjectOutputs` 增加可选的 `musicAnalysisJSON` 字段。旧项目没有该字段时仍能正常读取。

右侧属性面板提供：

- 导出音乐列表 JSON
- 导出音乐列表 TXT

JSON 使用 `MusicAnalysis` 的编码结果。TXT 按歌曲逐行输出名称、歌手、预计时间、置信度和来源。

## 错误处理

以下错误只影响音乐识别，不使转写失败：

- 未配置完整的讯飞凭证。
- 音频样本提取失败或超过大小限制。
- 鉴权失败、网络失败、额度耗尽或服务不可用。
- 所有样本均未匹配。
- 单个样本返回低分或无结果。

如果平台元数据已经提供歌曲，即使讯飞识别失败，仍显示平台结果，并附带补充识别失败提示。

以下错误仍按现有在线视频流程处理：

- 链接无效。
- `yt-dlp` 不支持链接。
- 视频私密、下架或地区受限。
- 登录态不足。
- 音频下载失败。

启用 Chrome Cookie 后仍失败时，不保存或人工修改 Cookie，只展示整理后的错误信息。

## 隐私、安全与商业迁移

开发版：

- 只上传用户主动启用识别后生成的 8 秒音频样本。
- 临时样本在分析结束后删除。
- 讯飞凭证存入本机 Keychain。
- 应用不保存平台账号密码或 Cookie。
- UI 明确提示音频样本会发送到讯飞歌曲识别服务。

正式公开发布前：

1. 不把讯飞 `APPID`、`APIKey` 或 `APISecret` 打包进 App。
2. 新增自有后端和 `BackendMusicRecognitionProvider`。
3. 后端验证用户身份、套餐和剩余额度。
4. 后端持有讯飞密钥并调用识别接口。
5. 失败请求不扣用户额度。
6. 后端记录调用次数、成本和错误码，但不记录原始音频。
7. 临时音频在识别结束后立即删除。
8. 更新隐私政策、用户协议和收费说明。

## 验证策略

### 单元测试

- 解析包含和不包含 `track`、`artist` 的 `yt-dlp` JSON。
- Chrome Cookie 参数只在用户选择后加入。
- 快速模式不超过 3 个样本。
- 深度模式按 45 秒分区且不超过 10 个样本。
- 口播较少的窗口优先。
- 讯飞请求签名对固定输入生成固定输出。
- 请求体使用 `acr_music`、`lame`、16 kHz 和单声道。
- 双层服务状态码都必须成功。
- Base64 响应可以解析为歌曲结果。
- 分数低于 70 或空结果不会生成确定歌曲。
- 相同歌曲结果去重并合并时间范围。
- 凭证不会写入 `UserDefaults` 或历史文件。
- 旧版 `project.json` 在缺少音乐输出字段时仍可解码。

### 集成验证

- 抖音公开视频：有平台音乐标签时可以显示。
- 小红书公开视频：无平台标签时可进入讯飞补充流程。
- B 站公开视频：可下载音频、提取样本并完成识别。
- Chrome 已登录场景：`--cookies-from-browser chrome` 可处理用户有权访问的视频。
- 未启用音乐识别时，现有转写行为、耗时和历史文件不受影响。
- 音乐识别失败时，文稿仍然归档成功。
- 使用测试凭证完成一次真实讯飞快速识别。

### 构建验证

```bash
xcodegen generate
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -configuration Debug build
xcodebuild -project DeanConversionTool.xcodeproj -scheme DeanConversionTool -configuration Debug test
./test_pipeline.sh
Scripts/check_dependencies.sh
```

## 验收标准

1. 在线视频区域可以选择关闭、快速识别或深度识别，默认关闭。
2. 抖音、小红书和 B 站公开视频继续使用现有 `yt-dlp` 流程。
3. 平台音乐标签存在时，无需讯飞调用也能显示结果。
4. 配置完整讯飞凭证后，快速模式最多查询 3 个样本。
5. 深度模式每 45 秒区间取样且最多查询 10 个样本。
6. 音乐结果包含名称、歌手、来源、置信度和可用的预计时间。
7. 音乐识别失败不会导致转写失败。
8. 历史项目可保存并重新加载 `music-analysis.json`。
9. 用户可以导出音乐结果为 JSON 和 TXT。
10. 用户可以选择按次读取 Chrome 登录状态，应用不保存密码或 Cookie。
11. 凭证只存入 macOS Keychain。
12. UI 明确提示音频样本会发送到讯飞。
13. 正式发布时可以只替换 Provider，不改动 UI、历史模型或分析协调流程。
