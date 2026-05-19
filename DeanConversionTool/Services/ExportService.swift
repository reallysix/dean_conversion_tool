import Foundation

/// Service for exporting transcripts in various formats
class ExportService {

    /// Export transcript to the specified format
    /// - Parameters:
    ///   - transcript: The transcript to export
    ///   - format: The export format
    ///   - outputPath: The output file path
    /// - Throws: ExportError if export fails
    func export(transcript: Transcript, format: ExportFormat, outputPath: String) throws {
        let content: String

        switch format {
        case .srt:
            content = generateSRT(transcript: transcript)
        case .txt:
            content = generateTXT(transcript: transcript)
        case .markdown:
            content = generateMarkdown(transcript: transcript)
        case .html:
            content = generateHTML(transcript: transcript)
        case .json:
            content = try generateJSON(transcript: transcript)
        }

        try content.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }

    /// Generate SRT (SubRip) format
    private func generateSRT(transcript: Transcript) -> String {
        var srt = ""
        for (index, segment) in transcript.segments.enumerated() {
            srt += "\(index + 1)\n"
            srt += "\(segment.srtTimestamp)\n"
            srt += "\(segment.text)\n\n"
        }
        return srt
    }

    /// Generate plain text format
    private func generateTXT(transcript: Transcript) -> String {
        var txt = ""
        for segment in transcript.segments {
            if let speaker = segment.speaker {
                txt += "[\(speaker)] \(segment.text)\n"
            } else {
                txt += "\(segment.text)\n"
            }
        }
        return txt
    }

    /// Generate Markdown format
    private func generateMarkdown(transcript: Transcript) -> String {
        var md = "# 逐字稿\n\n"
        md += "来源: \(transcript.sourceURL.lastPathComponent)\n"
        md += "创建时间: \(transcript.createdAt.formatted())\n"
        md += "时长: \(formatDuration(transcript.duration))\n"
        md += "说话人数量: \(transcript.speakerCount)\n\n"
        md += "---\n\n"

        var currentSpeaker: String?
        for segment in transcript.segments {
            if let speaker = segment.speaker, speaker != currentSpeaker {
                currentSpeaker = speaker
                md += "\n### \(speaker)\n\n"
            }

            let timestamp = segment.displayTimestamp
            md += "**\(timestamp)** \(segment.text)\n\n"
        }

        return md
    }

    /// Generate HTML format
    private func generateHTML(transcript: Transcript) -> String {
        var html = """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>逐字稿 - \(transcript.sourceURL.lastPathComponent)</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; line-height: 1.6; }
                .header { border-bottom: 2px solid #007AFF; padding-bottom: 10px; margin-bottom: 20px; }
                .segment { margin-bottom: 15px; padding: 10px; border-radius: 8px; background: #f5f5f5; }
                .segment:hover { background: #e8e8e8; }
                .timestamp { color: #007AFF; font-weight: bold; margin-right: 10px; }
                .speaker { color: #666; font-weight: bold; margin-right: 10px; }
                .text { margin-top: 5px; }
            </style>
        </head>
        <body>
            <div class="header">
                <h1>逐字稿</h1>
                <p>来源: \(transcript.sourceURL.lastPathComponent)</p>
                <p>创建时间: \(transcript.createdAt.formatted())</p>
                <p>时长: \(formatDuration(transcript.duration)) | 说话人: \(transcript.speakerCount)</p>
            </div>

        """

        var currentSpeaker: String?
        for segment in transcript.segments {
            if let speaker = segment.speaker, speaker != currentSpeaker {
                currentSpeaker = speaker
                html += "            <h3>\(speaker)</h3>\n"
            }

            let timestamp = segment.displayTimestamp

            html += """
                        <div class="segment">
                            <span class="timestamp">\(timestamp)</span>
                            <span class="speaker">\(segment.speaker ?? "")</span>
                            <div class="text">\(segment.text)</div>
                        </div>

            """
        }

        html += """
                </body>
                </html>
        """

        return html
    }

    /// Generate JSON format
    private func generateJSON(transcript: Transcript) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(transcript)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Format duration for display
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    /// Get default file extension for format
    func fileExtension(for format: ExportFormat) -> String {
        switch format {
        case .srt: return "srt"
        case .txt: return "txt"
        case .markdown: return "md"
        case .html: return "html"
        case .json: return "json"
        }
    }

    /// Get format display name
    func formatDisplayName(for format: ExportFormat) -> String {
        switch format {
        case .srt: return "SRT 字幕文件"
        case .txt: return "纯文本"
        case .markdown: return "Markdown"
        case .html: return "HTML 网页"
        case .json: return "JSON 数据"
        }
    }
}

/// Export format options
enum ExportFormat: String, CaseIterable {
    case srt = "srt"
    case txt = "txt"
    case markdown = "markdown"
    case html = "html"
    case json = "json"

    var displayName: String {
        switch self {
        case .srt: return "SRT 字幕文件"
        case .txt: return "纯文本"
        case .markdown: return "Markdown"
        case .html: return "HTML 网页"
        case .json: return "JSON 数据"
        }
    }
}

/// Errors that can occur during export
enum ExportError: LocalizedError {
    case invalidPath
    case writeFailed(Error)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidPath:
            return "输出路径无效"
        case .writeFailed(let error):
            return "文件写入失败：\(error.localizedDescription)"
        case .encodingFailed:
            return "文稿编码失败"
        }
    }
}
