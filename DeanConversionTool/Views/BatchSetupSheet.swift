import SwiftUI
import UniformTypeIdentifiers

/// Sheet for configuring batch processing before starting
struct BatchSetupSheet: View {
    @ObservedObject var viewModel: TranscriptViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat: ExportFormat = .txt
    @State private var exportDirectory: URL?
    @State private var showDirectoryPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("批量处理")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Text("\(viewModel.batchQueue.count) 个文件")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // File list
            VStack(alignment: .leading, spacing: 8) {
                Text("待处理文件")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(viewModel.batchQueue, id: \.self) { url in
                            HStack(spacing: 8) {
                                Image(systemName: iconForFile(url))
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.accent)
                                    .frame(width: 16)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 6)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()
                .padding(.top, 12)

            // Settings
            VStack(spacing: 16) {
                // Export format
                HStack {
                    Text("导出格式")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    Picker("", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }

                // Export directory
                HStack {
                    Text("导出目录")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    if let dir = exportDirectory {
                        Text(dir.lastPathComponent)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: 100, alignment: .trailing)
                    }
                    Button(action: { showDirectoryPicker = true }) {
                        Text(exportDirectory == nil ? "选择目录" : "更改")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            // Buttons
            HStack(spacing: 12) {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.surface)
                .cornerRadius(AppTheme.cornerRadiusSmall)

                Spacer()

                Button(action: startBatch) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                        Text("开始处理")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(exportDirectory != nil ? AppTheme.accent : AppTheme.textTertiary)
                    .cornerRadius(AppTheme.cornerRadiusSmall)
                }
                .buttonStyle(.plain)
                .disabled(exportDirectory == nil)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 480)
        .background(AppTheme.background)
        .onAppear {
            selectedFormat = viewModel.batchExportFormat
        }
        .fileImporter(
            isPresented: $showDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                exportDirectory = url
            }
        }
    }

    private func startBatch() {
        guard let directory = exportDirectory else { return }
        viewModel.batchExportFormat = selectedFormat
        viewModel.batchExportDirectory = directory
        dismiss()
        viewModel.startBatch()
    }

    private func iconForFile(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let videoExtensions = ["mp4", "mov", "avi", "mkv", "webm", "m4v"]
        return videoExtensions.contains(ext) ? "film" : "waveform"
    }
}

/// Sheet showing batch processing results
struct BatchSummarySheet: View {
    @ObservedObject var viewModel: TranscriptViewModel
    @Environment(\.dismiss) private var dismiss

    private var succeeded: Int {
        viewModel.batchResults.filter { $0.success }.count
    }

    private var failed: Int {
        viewModel.batchResults.filter { !$0.success }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("批量处理完成")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Summary stats
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("\(succeeded)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.green)
                    Text("成功")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)

                if failed > 0 {
                    VStack(spacing: 4) {
                        Text("\(failed)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(AppTheme.danger)
                        Text("失败")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 20)

            // Export location
            if let dir = viewModel.batchExportDirectory {
                HStack {
                    Text("导出位置：")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSecondary)
                    Text(dir.path)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("打开文件夹") {
                        NSWorkspace.shared.open(dir)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.accent)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            // Failed files list
            if failed > 0 {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("失败文件")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.danger)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)

                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(viewModel.batchResults.filter { !$0.success }, id: \.url) { result in
                                HStack(spacing: 8) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(AppTheme.danger)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.url.lastPathComponent)
                                            .font(.system(size: 12))
                                            .foregroundColor(AppTheme.textPrimary)
                                            .lineLimit(1)
                                        if let error = result.error {
                                            Text(error)
                                                .font(.system(size: 10))
                                                .foregroundColor(AppTheme.textSecondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
            }

            Divider()
                .padding(.top, 12)

            // Close button
            HStack {
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(AppTheme.accent)
                .cornerRadius(AppTheme.cornerRadiusSmall)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 480)
        .background(AppTheme.background)
    }
}
